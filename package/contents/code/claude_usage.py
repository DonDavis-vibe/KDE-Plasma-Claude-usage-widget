#!/usr/bin/env python3
"""Backend for the Claude Usage plasmoid.

Prints one JSON object to stdout:
  - "used":   token counts from the local Claude Code logs (~/.claude/projects)
  - "limits": plan utilization from Anthropic's OAuth usage endpoint (the same
              data `/usage` in Claude Code shows), or an error string.

The limits response is cached for a short time so a 60s widget refresh does
not hammer the endpoint.

Hardening notes (keep these when changing the code):
  * Everything read from disk or from the network is treated as untrusted:
    types are checked, sizes are capped, numbers are clamped.
  * The OAuth token is only ever sent to the two fixed https URLs below and
    redirects are refused, so it cannot be forwarded to another host.
  * Credentials are rewritten atomically with owner-only permissions, under a
    lock, and only after the new tokens have been validated.
  * The script never prints tokens and never lets an exception escape: stdout is
    always one valid JSON object.
"""
import fcntl
import json
import math
import os
import re
import secrets
import stat
import sys
import time
import urllib.error
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR") or HOME / ".claude")
PROJECTS = CONFIG_DIR / "projects"
CREDS = CONFIG_DIR / ".credentials.json"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "claude-usage-widget"
LIMITS_CACHE = CACHE_DIR / "limits.json"
LOCK_FILE = CACHE_DIR / "refresh.lock"
LIMITS_TTL = 120  # seconds

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
BLOCK = timedelta(hours=5)

# Limits for untrusted input
MAX_LINE = 4 * 1024 * 1024        # one log line
MAX_HTTP_BYTES = 1024 * 1024      # one HTTP response
MAX_CACHE_BYTES = 256 * 1024
MAX_CREDS_BYTES = 256 * 1024
SCAN_BUDGET = 15.0                # seconds for scanning the logs
MAX_FILES = 20000
MAX_TOKENS = 10 ** 12
TOKEN_RE = re.compile(r"[\x21-\x7e]{8,8192}")  # printable ASCII, no whitespace

SYNTHETIC_MODEL = "‹synthetic›"       # clean_text("<synthetic>")

MSG_LOGIN_EXPIRED = "Login abgelaufen – im Terminal `claude` → /login"
MSG_LOGIN_EXPIRED_NOREFRESH = "Login abgelaufen – `claude` im Terminal starten"
MSG_NO_LOGIN = "Kein Claude-Code-Login gefunden"


class LoginExpired(RuntimeError):
    pass


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def clean_text(value, limit=160):
    """One printable line, capped, without markup characters (shown in the UI)."""
    s = " ".join(str(value).split())
    s = "".join(ch for ch in s if ch.isprintable())
    return s.replace("<", "‹").replace(">", "›")[:limit]


def clean_error(value):
    return clean_text(value) or "Fehler"


def safe_int(v):
    """Non-negative int below MAX_TOKENS, 0 for anything else."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return 0
    if isinstance(v, float) and not math.isfinite(v):
        return 0
    return int(min(max(v, 0), MAX_TOKENS))


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def atomic_write(path, text, mode=0o600):
    """Write `path` atomically: private temp file next to it, fsync, rename.
    A symlinked target is written through, so dotfile managers keep working."""
    target = Path(os.path.realpath(path))
    tmp = target.with_name(".%s.%d.%s.tmp" % (target.name, os.getpid(), secrets.token_hex(4)))
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(tmp, flags, mode)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_json_file(path, max_bytes):
    """Read a small regular file as a JSON object; refuses oversized files."""
    with open(path, "rb") as fh:
        raw = fh.read(max_bytes + 1)
    if len(raw) > max_bytes:
        raise ValueError("Datei zu groß: %s" % path.name)
    data = json.loads(raw.decode("utf-8", errors="strict"))
    if not isinstance(data, dict):
        raise ValueError("Unerwartetes Format: %s" % path.name)
    return data


def private_dir(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass


# --------------------------------------------------------------------------
# Local logs
# --------------------------------------------------------------------------

def parse_ts(s):
    if not isinstance(s, str):
        return None
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def iter_log_files(deadline, stats):
    """Regular *.jsonl files below PROJECTS. Symlinks (files and directories) are
    not followed, the walk stops at the deadline or after MAX_FILES."""
    count = 0
    for root, dirs, files in os.walk(PROJECTS, followlinks=False):
        for name in files:
            if not name.endswith(".jsonl"):
                continue
            if time.monotonic() > deadline or count >= MAX_FILES:
                stats["truncated"] = True
                return
            path = os.path.join(root, name)
            try:
                st = os.lstat(path)
            except OSError:
                continue
            if stat.S_ISREG(st.st_mode):
                count += 1
                yield path, st


def iter_entries(since, deadline, stats):
    """Yield (timestamp, model, usage) for every assistant message since `since`,
    deduplicated by message id + request id (Claude Code logs one line per
    content block, all carrying the same usage)."""
    seen = set()
    cutoff = since.timestamp()
    for path, st in iter_log_files(deadline, stats):
        if st.st_mtime < cutoff:
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                n = 0
                while True:
                    line = fh.readline(MAX_LINE)
                    if not line:
                        break
                    if len(line) >= MAX_LINE and not line.endswith("\n"):
                        # oversized line: skip the rest of it
                        while True:
                            rest = fh.readline(MAX_LINE)
                            if not rest or rest.endswith("\n"):
                                break
                        continue
                    n += 1
                    if n % 5000 == 0 and time.monotonic() > deadline:
                        stats["truncated"] = True
                        break
                    if '"usage"' not in line:
                        continue
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(rec, dict):
                        continue
                    msg = rec.get("message")
                    if not isinstance(msg, dict) or not isinstance(msg.get("usage"), dict):
                        continue
                    ts = parse_ts(rec.get("timestamp"))
                    if ts is None or ts < since:
                        continue
                    mid, rid = msg.get("id"), rec.get("requestId")
                    if mid is not None or rid is not None:
                        key = (str(mid), str(rid))
                        if key in seen:
                            continue
                        seen.add(key)
                    model = msg.get("model")
                    model = clean_text(model, 80) if isinstance(model, str) and model else "?"
                    yield ts, model, msg["usage"]
        except OSError:
            continue


def empty_counts():
    return {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0, "total": 0, "messages": 0}


def add(counts, u):
    i = safe_int(u.get("input_tokens"))
    o = safe_int(u.get("output_tokens"))
    cw = safe_int(u.get("cache_creation_input_tokens"))
    cr = safe_int(u.get("cache_read_input_tokens"))
    counts["input"] += i
    counts["output"] += o
    counts["cache_write"] += cw
    counts["cache_read"] += cr
    counts["total"] += i + o + cw + cr
    counts["messages"] += 1


def floor_hour(dt):
    return dt.replace(minute=0, second=0, microsecond=0)


def local_usage(now):
    local_now = now.astimezone()
    today_start = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today_start - timedelta(days=today_start.weekday())
    since = min(week_start, now - BLOCK * 2)

    stats = {"truncated": False}
    deadline = time.monotonic() + SCAN_BUDGET
    entries = sorted(iter_entries(since, deadline, stats), key=lambda e: e[0])

    today, week = empty_counts(), empty_counts()
    models = {}
    for ts, model, u in entries:
        if ts >= week_start:
            add(week, u)
        if ts >= today_start:
            add(today, u)
            if model != SYNTHETIC_MODEL:     # Claude Code's internal placeholder, not a real model
                add(models.setdefault(model, empty_counts()), u)

    # Rebuild 5h blocks the way Claude's limits work: a block starts at the
    # (hour-floored) first message after the previous block ended.
    block_start = block_end = None
    block = empty_counts()
    for ts, _model, u in entries:
        if block_end is None or ts >= block_end:
            block_start = floor_hour(ts)
            block_end = block_start + BLOCK
            block = empty_counts()
        add(block, u)
    active = block_end is not None and now < block_end

    return {
        "block": {
            "active": active,
            "start": block_start.isoformat() if active else None,
            "end": block_end.isoformat() if active else None,
            "tokens": block if active else empty_counts(),
        },
        "today": today,
        "week": week,
        "models_today": {m: c["total"] for m, c in sorted(models.items(), key=lambda kv: -kv[1]["total"])},
        "truncated": stats["truncated"],
    }


# --------------------------------------------------------------------------
# HTTP (only the two fixed https endpoints, no redirects, capped responses)
# --------------------------------------------------------------------------

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse redirects: urllib would forward the Authorization header."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _require_https(url):
    if not url.startswith("https://"):
        raise ValueError("Nur https erlaubt")


def http_json(url, data=None, headers=None, timeout=10):
    _require_https(url)
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers or {}, method="POST" if body else "GET")
    if body:
        req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "claude-usage-plasmoid/1.1")
    with _OPENER.open(req, timeout=timeout) as resp:
        raw = resp.read(MAX_HTTP_BYTES + 1)
    if len(raw) > MAX_HTTP_BYTES:
        raise ValueError("Antwort zu groß")
    out = json.loads(raw.decode("utf-8"))
    if not isinstance(out, dict):
        raise ValueError("Unerwartete Antwort")
    return out


# --------------------------------------------------------------------------
# Credentials
# --------------------------------------------------------------------------

def load_creds():
    return read_json_file(CREDS, MAX_CREDS_BYTES)


def oauth_of(creds):
    oauth = creds.get("claudeAiOauth")
    if not isinstance(oauth, dict):
        raise ValueError("Kein OAuth-Login in der Credentials-Datei")
    return oauth


def token_valid(oauth, margin_ms=60_000):
    exp = oauth.get("expiresAt")
    tok = oauth.get("accessToken")
    return is_number(exp) and exp > time.time() * 1000 + margin_ms \
        and isinstance(tok, str) and bool(TOKEN_RE.fullmatch(tok))


@contextmanager
def refresh_lock(timeout=15.0):
    """Serialise refreshes between widget instances (Claude Code itself does not
    use this lock, hence the re-read before and after the network call)."""
    private_dir(CACHE_DIR)
    fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise RuntimeError("Token-Erneuerung läuft bereits")
                time.sleep(0.2)
        yield
    finally:
        os.close(fd)  # releases the lock


def refresh_token():
    """Refresh the OAuth access token and write it back like Claude Code does,
    so the CLI keeps working with the rotated refresh token. Returns the oauth
    dict to use."""
    with refresh_lock():
        creds = load_creds()
        oauth = oauth_of(creds)
        if token_valid(oauth):          # somebody else refreshed in the meantime
            return oauth
        rt = oauth.get("refreshToken")
        if not isinstance(rt, str) or not TOKEN_RE.fullmatch(rt):
            raise LoginExpired(MSG_LOGIN_EXPIRED)
        try:
            res = http_json(TOKEN_URL, {
                "grant_type": "refresh_token",
                "refresh_token": rt,
                "client_id": CLIENT_ID,
            })
        except urllib.error.HTTPError as e:
            e.close()
            if e.code in (400, 401, 403):
                raise LoginExpired(MSG_LOGIN_EXPIRED) from None
            raise

        at = res.get("access_token")
        if not isinstance(at, str) or not TOKEN_RE.fullmatch(at):
            raise ValueError("Ungültige Token-Antwort")
        new_rt = res.get("refresh_token")
        if not (isinstance(new_rt, str) and TOKEN_RE.fullmatch(new_rt)):
            new_rt = rt                  # server did not rotate it
        expires_in = res.get("expires_in")
        if not (is_number(expires_in) and 0 < expires_in <= 30 * 86400):
            expires_in = None

        # Compare-and-swap: if the file changed while we were on the network,
        # keep what is there instead of overwriting it.
        latest = load_creds()
        current = oauth_of(latest)
        if current.get("refreshToken") != rt and token_valid(current):
            return current
        merged = dict(current)
        merged["accessToken"] = at
        merged["refreshToken"] = new_rt
        if expires_in:
            merged["expiresAt"] = int((time.time() + expires_in) * 1000)
        latest["claudeAiOauth"] = merged
        try:
            mode = stat.S_IMODE(os.stat(CREDS).st_mode) & 0o600 or 0o600
        except OSError:
            mode = 0o600
        atomic_write(CREDS, json.dumps(latest), mode)
        return merged


# --------------------------------------------------------------------------
# Plan limits
# --------------------------------------------------------------------------

def clean_limit(key, label, percent, resets_at):
    """One validated limit entry or None."""
    if not is_number(percent):
        return None
    if not isinstance(resets_at, str) or parse_ts(resets_at) is None:
        resets_at = None
    return {
        "key": clean_text(key, 64),
        "label": clean_text(label, 64),
        "percent": float(min(max(percent, 0), 100)),
        "resets_at": resets_at[:64] if resets_at else None,
    }


def normalise_limits(raw):
    """Turn the endpoint response into a list of {key, label, percent, resets_at}.

    Prefers the generic "limits" list; falls back to the older top-level
    windows. Only known keys are used, the response also carries internal
    codenamed fields that are not plan limits."""
    kinds = {
        "session": ("five_hour", "5 Stunden"),
        "weekly_all": ("seven_day", "Woche"),
        "weekly_opus": ("seven_day_opus", "Woche Opus"),
        "weekly_sonnet": ("seven_day_sonnet", "Woche Sonnet"),
    }
    out = []
    if isinstance(raw.get("limits"), list) and raw["limits"]:
        for lim in raw["limits"][:32]:
            if not isinstance(lim, dict):
                continue
            kind = lim.get("kind")
            kind = kind if isinstance(kind, str) and kind else "?"
            key, label = kinds.get(kind, (kind, kind.replace("_", " ").capitalize()))
            item = clean_limit(key, label, lim.get("percent"), lim.get("resets_at"))
            if item:
                out.append(item)
        return out

    labels = {
        "five_hour": "5 Stunden",
        "seven_day": "Woche",
        "seven_day_opus": "Woche Opus",
        "seven_day_sonnet": "Woche Sonnet",
        "seven_day_oauth_apps": "Woche Apps",
    }
    for key, val in raw.items():
        if key not in labels or not isinstance(val, dict):
            continue
        item = clean_limit(key, labels[key], val.get("utilization"), val.get("resets_at"))
        if item:
            out.append(item)
    order = {k: i for i, k in enumerate(labels)}
    out.sort(key=lambda e: order.get(e["key"], 99))
    return out


def read_limits_cache():
    """The cached result if it is fresh and well-formed, else None."""
    try:
        st = os.lstat(LIMITS_CACHE)
        if not stat.S_ISREG(st.st_mode):
            return None
        cached = read_json_file(LIMITS_CACHE, MAX_CACHE_BYTES)
        fetched = cached.get("fetched")
        age = time.time() - fetched if is_number(fetched) else -1
        if not 0 <= age < LIMITS_TTL or not isinstance(cached.get("items"), list):
            return None
        items = []
        for it in cached["items"][:32]:
            if isinstance(it, dict):
                item = clean_limit(it.get("key"), it.get("label"), it.get("percent"), it.get("resets_at"))
                if item:
                    items.append(item)
        err, plan = cached.get("error"), cached.get("plan")
        return {
            "fetched": fetched,
            "items": items,
            "error": clean_error(err) if err else None,
            "plan": clean_text(plan, 32) if isinstance(plan, str) else None,
        }
    except (OSError, ValueError):
        return None


def fetch_limits(allow_refresh):
    cached = read_limits_cache()
    if cached is not None:
        return cached

    result = {"fetched": time.time(), "items": [], "error": None, "plan": None}
    try:
        oauth = oauth_of(load_creds())
        plan = oauth.get("subscriptionType")
        result["plan"] = clean_text(plan, 32) if isinstance(plan, str) else None
        if not token_valid(oauth):
            if not allow_refresh:
                raise LoginExpired(MSG_LOGIN_EXPIRED_NOREFRESH)
            rte = oauth.get("refreshTokenExpiresAt")
            if is_number(rte) and rte < time.time() * 1000:
                raise LoginExpired(MSG_LOGIN_EXPIRED)
            oauth = refresh_token()
        raw = http_json(USAGE_URL, headers={
            "Authorization": "Bearer " + oauth["accessToken"],
            "anthropic-beta": "oauth-2025-04-20",
        })
        result["items"] = normalise_limits(raw)
    except FileNotFoundError:
        result["error"] = MSG_NO_LOGIN
    except LoginExpired as e:
        result["error"] = str(e)
    except urllib.error.HTTPError as e:
        e.close()
        result["error"] = MSG_LOGIN_EXPIRED if e.code in (401, 403) else "HTTP %d" % e.code
    except Exception as e:  # noqa: BLE001 - widget must never crash
        result["error"] = clean_error(e) if str(e) else type(e).__name__

    try:
        private_dir(CACHE_DIR)
        atomic_write(LIMITS_CACHE, json.dumps(result), 0o600)
    except OSError:
        pass
    return result


def main():
    os.umask(0o077)  # anything this script creates is private
    allow_refresh = "--no-refresh" not in sys.argv
    if "--force" in sys.argv:
        try:
            LIMITS_CACHE.unlink()
        except OSError:
            pass
    now = datetime.now(timezone.utc)
    out = {"now": now.isoformat()}
    try:
        out["used"] = local_usage(now)
    except Exception as e:  # noqa: BLE001
        out["used"] = None
        out["used_error"] = clean_error(e)
    try:
        out["limits"] = fetch_limits(allow_refresh)
    except Exception as e:  # noqa: BLE001
        out["limits"] = {"fetched": time.time(), "items": [], "error": clean_error(e), "plan": None}
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
