#!/usr/bin/env python3
"""Tests for the hardened backend (package/contents/code/claude_usage.py).

Run:  python3 -I tests/test_backend.py

Everything runs against temporary directories and a local HTTP server. The real
~/.claude credentials and the real Anthropic endpoints are never touched.
"""
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "package" / "contents" / "code" / "claude_usage.py"


def load_module():
    spec = importlib.util.spec_from_file_location("claude_usage_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class MockServer:
    """Tiny HTTP server. `routes[path]` is a callable(handler, body) -> None."""

    def __init__(self):
        self.routes = {}
        self.requests = []
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _serve(self):
                n = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(n) if n else b""
                outer.requests.append((self.command, self.path, dict(self.headers), body))
                fn = outer.routes.get(self.path)
                if fn is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                fn(self, body)

            do_GET = do_POST = _serve

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.url = "http://127.0.0.1:%d" % self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def reply_json(obj, status=200):
    def fn(h, body):
        data = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        h.send_response(status)
        h.send_header("Content-Type", "application/json")
        h.send_header("Content-Length", str(len(data)))
        h.end_headers()
        h.wfile.write(data)
    return fn


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.m = load_module()
        m = self.m
        m.CONFIG_DIR = self.dir / "claude"
        m.PROJECTS = m.CONFIG_DIR / "projects"
        m.CREDS = m.CONFIG_DIR / ".credentials.json"
        m.CACHE_DIR = self.dir / "cache"
        m.LIMITS_CACHE = m.CACHE_DIR / "limits.json"
        m.LOCK_FILE = m.CACHE_DIR / "refresh.lock"
        m.PROJECTS.mkdir(parents=True)
        self.server = MockServer()
        m.TOKEN_URL = self.server.url + "/token"
        m.USAGE_URL = self.server.url + "/usage"
        m._require_https = lambda url: None  # tests talk to 127.0.0.1 over http

    def tearDown(self):
        self.server.close()
        self.tmp.cleanup()

    def write_creds(self, **over):
        oauth = {
            "accessToken": "old-access-token-123",
            "refreshToken": "old-refresh-token-456",
            "expiresAt": int((time.time() - 3600) * 1000),
            "refreshTokenExpiresAt": int((time.time() + 86400) * 1000),
            "subscriptionType": "pro",
        }
        oauth.update(over)
        data = {"claudeAiOauth": oauth, "otherKey": {"keep": "me"}}
        self.m.CREDS.write_text(json.dumps(data))
        os.chmod(self.m.CREDS, 0o600)
        return data


# --------------------------------------------------------------------------

class TestHelpers(Base):
    def test_clean_text_strips_markup_and_newlines(self):
        out = self.m.clean_text("a <b>bold</b>\nline\x00two", 100)
        self.assertNotIn("<", out)
        self.assertNotIn("\n", out)
        self.assertNotIn("\x00", out)

    def test_clean_text_caps_length(self):
        self.assertEqual(len(self.m.clean_text("x" * 1000, 50)), 50)

    def test_safe_int_clamps_and_rejects(self):
        f = self.m.safe_int
        self.assertEqual(f("5"), 0)
        self.assertEqual(f(None), 0)
        self.assertEqual(f(True), 0)
        self.assertEqual(f(-5), 0)
        self.assertEqual(f(float("nan")), 0)
        self.assertEqual(f(float("inf")), 0)
        self.assertEqual(f(1e30), self.m.MAX_TOKENS)
        self.assertEqual(f(42), 42)

    def test_parse_ts_naive_becomes_aware(self):
        dt = self.m.parse_ts("2026-10-17T10:00:00")
        self.assertIsNotNone(dt.tzinfo)
        self.assertIsNone(self.m.parse_ts(123))
        self.assertIsNone(self.m.parse_ts("not a date"))

    def test_atomic_write_is_private_and_leaves_no_temp(self):
        p = self.dir / "f.json"
        self.m.atomic_write(p, '{"a":1}', 0o600)
        self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600)
        self.assertEqual([x.name for x in self.dir.iterdir() if x.name.endswith(".tmp")], [])
        self.assertEqual(json.loads(p.read_text()), {"a": 1})

    def test_atomic_write_follows_symlink(self):
        real = self.dir / "real.json"
        real.write_text("{}")
        link = self.dir / "link.json"
        link.symlink_to(real)
        self.m.atomic_write(link, '{"x":2}', 0o600)
        self.assertTrue(link.is_symlink())            # still a link
        self.assertEqual(json.loads(real.read_text()), {"x": 2})

    def test_read_json_file_rejects_oversized_and_non_objects(self):
        p = self.dir / "big.json"
        p.write_text('{"a":"' + "x" * 200 + '"}')
        with self.assertRaises(ValueError):
            self.m.read_json_file(p, 50)
        q = self.dir / "list.json"
        q.write_text("[1,2]")
        with self.assertRaises(ValueError):
            self.m.read_json_file(q, 1000)


# --------------------------------------------------------------------------

class TestLogs(Base):
    def line(self, ts, mid, model="claude-x", usage=None, **extra):
        rec = {"timestamp": ts, "requestId": "r-" + mid,
               "message": {"id": mid, "model": model,
                           "usage": usage if usage is not None else {"input_tokens": 1, "output_tokens": 2}}}
        rec.update(extra)
        return json.dumps(rec)

    def test_survives_hostile_log_content(self):
        now = datetime.now(timezone.utc)
        iso = now.isoformat()
        naive = now.replace(tzinfo=None).isoformat()
        f = self.m.PROJECTS / "p" / "s.jsonl"
        f.parent.mkdir()
        lines = [
            self.line(iso, "a", usage={"input_tokens": 10, "output_tokens": 20}),
            self.line(iso, "a", usage={"input_tokens": 10, "output_tokens": 20}),   # duplicate
            self.line(naive, "b", usage={"input_tokens": 5}),                        # naive timestamp
            self.line(iso, "c", usage={"input_tokens": "abc", "output_tokens": None}),
            self.line(iso, "d", usage={"input_tokens": -5, "output_tokens": 1e30}),
            self.line(iso, "e", usage={"input_tokens": True}),
            self.line(iso, "f", model="<script>alert(1)</script>\nx"),
            self.line(iso, "g", id=["unhashable"]),                                  # odd extra field
            json.dumps({"message": {"id": ["x"], "usage": {}}, "requestId": {"a": 1}, "timestamp": iso}),
            "[1,2,3]",
            "not json at all but has \"usage\"",
            json.dumps({"message": "str", "timestamp": iso}),
        ]
        f.write_text("\n".join(lines) + "\n")
        out = self.m.local_usage(now)
        # a: 10 (duplicate ignored), b: 5 (naive timestamp counts), c/d/e: 0 (text, negative, bool),
        # f and g: default usage with 1 input token each, plus one line with odd id types (counts, 0 tokens)
        self.assertEqual(out["today"]["input"], 17)
        self.assertEqual(out["today"]["messages"], 8)   # + the line with odd id/requestId types
        # huge numbers are clamped instead of overflowing the totals
        self.assertEqual(out["today"]["output"], 20 + self.m.MAX_TOKENS + 2 + 2)
        for model in out["models_today"]:
            self.assertNotIn("<", model)
            self.assertNotIn("\n", model)

    def test_synthetic_placeholder_is_not_listed_as_a_model(self):
        now = datetime.now(timezone.utc)
        f = self.m.PROJECTS / "p.jsonl"
        f.write_text("\n".join([
            self.line(now.isoformat(), "s", model="<synthetic>", usage={"input_tokens": 0, "output_tokens": 0}),
            self.line(now.isoformat(), "r", model="claude-real", usage={"input_tokens": 4}),
        ]) + "\n")
        out = self.m.local_usage(now)
        self.assertEqual(list(out["models_today"]), ["claude-real"])
        self.assertEqual(out["today"]["messages"], 2)       # still counted as a message

    def test_dedup_counts_once(self):
        now = datetime.now(timezone.utc)
        f = self.m.PROJECTS / "p.jsonl"
        f.write_text("\n".join([self.line(now.isoformat(), "a", usage={"input_tokens": 7})] * 3) + "\n")
        out = self.m.local_usage(now)
        self.assertEqual(out["today"]["input"], 7)
        self.assertEqual(out["today"]["messages"], 1)

    def test_oversized_line_is_skipped_not_loaded(self):
        self.m.MAX_LINE = 2000
        now = datetime.now(timezone.utc)
        f = self.m.PROJECTS / "p.jsonl"
        big = self.line(now.isoformat(), "big", usage={"input_tokens": 999}) + "x" * 10000
        ok = self.line(now.isoformat(), "ok", usage={"input_tokens": 3})
        f.write_text(big + "\n" + ok + "\n")
        out = self.m.local_usage(now)
        self.assertEqual(out["today"]["input"], 3)

    def test_symlinks_are_not_followed(self):
        now = datetime.now(timezone.utc)
        outside = self.dir / "outside"
        outside.mkdir()
        (outside / "x.jsonl").write_text(self.line(now.isoformat(), "o", usage={"input_tokens": 100}) + "\n")
        (self.m.PROJECTS / "linkdir").symlink_to(outside)
        (self.m.PROJECTS / "linkfile.jsonl").symlink_to(outside / "x.jsonl")
        out = self.m.local_usage(now)
        self.assertEqual(out["today"]["messages"], 0)

    def test_scan_budget_truncates(self):
        self.m.SCAN_BUDGET = -1.0
        now = datetime.now(timezone.utc)
        (self.m.PROJECTS / "a.jsonl").write_text(self.line(now.isoformat(), "a") + "\n")
        out = self.m.local_usage(now)
        self.assertTrue(out["truncated"])

    def test_missing_projects_dir_is_fine(self):
        self.m.PROJECTS = self.dir / "does-not-exist"
        out = self.m.local_usage(datetime.now(timezone.utc))
        self.assertEqual(out["week"]["messages"], 0)
        self.assertFalse(out["block"]["active"])


# --------------------------------------------------------------------------

class TestHttp(Base):
    def test_https_is_required_by_default(self):
        m = load_module()
        with self.assertRaises(ValueError):
            m.http_json("http://example.com/")

    def test_redirects_are_refused_and_token_not_forwarded(self):
        other = MockServer()
        other.routes["/stolen"] = reply_json({"ok": True})
        self.server.routes["/usage"] = lambda h, b: (
            h.send_response(302), h.send_header("Location", other.url + "/stolen"), h.end_headers())
        try:
            with self.assertRaises(urllib.error.HTTPError) as cm:
                self.m.http_json(self.m.USAGE_URL, headers={"Authorization": "Bearer secret-token"})
            self.assertEqual(cm.exception.code, 302)
            time.sleep(0.2)
            self.assertEqual(other.requests, [])       # nothing reached the other host
        finally:
            other.close()

    def test_oversized_response_is_rejected(self):
        self.m.MAX_HTTP_BYTES = 100
        self.server.routes["/usage"] = reply_json({"x": "y" * 500})
        with self.assertRaises(ValueError):
            self.m.http_json(self.m.USAGE_URL)

    def test_non_object_response_is_rejected(self):
        self.server.routes["/usage"] = reply_json(b"[1,2,3]")
        with self.assertRaises(ValueError):
            self.m.http_json(self.m.USAGE_URL)


# --------------------------------------------------------------------------

class TestRefresh(Base):
    def new_tokens(self, **over):
        t = {"access_token": "new-access-token-abcdef", "refresh_token": "new-refresh-token-xyz",
             "expires_in": 28800}
        t.update(over)
        return t

    def test_success_rewrites_creds_atomically_and_privately(self):
        self.write_creds()
        self.server.routes["/token"] = reply_json(self.new_tokens())
        oauth = self.m.refresh_token()
        self.assertEqual(oauth["accessToken"], "new-access-token-abcdef")
        saved = json.loads(self.m.CREDS.read_text())
        self.assertEqual(saved["claudeAiOauth"]["refreshToken"], "new-refresh-token-xyz")
        self.assertEqual(saved["otherKey"], {"keep": "me"})                 # untouched keys survive
        self.assertEqual(saved["claudeAiOauth"]["subscriptionType"], "pro")
        self.assertGreater(saved["claudeAiOauth"]["expiresAt"], time.time() * 1000)
        self.assertEqual(stat.S_IMODE(self.m.CREDS.stat().st_mode), 0o600)
        leftovers = [p.name for p in self.m.CONFIG_DIR.iterdir() if p.name.endswith(".tmp")]
        self.assertEqual(leftovers, [])
        sent = json.loads(self.server.requests[0][3])
        self.assertEqual(sent["refresh_token"], "old-refresh-token-456")

    def test_stricter_original_mode_is_kept_never_widened(self):
        self.write_creds()
        os.chmod(self.m.CREDS, 0o400)
        self.server.routes["/token"] = reply_json(self.new_tokens())
        self.m.refresh_token()
        self.assertEqual(stat.S_IMODE(self.m.CREDS.stat().st_mode), 0o400)

    def test_symlinked_creds_stay_a_symlink(self):
        self.write_creds()
        real = self.dir / "dotfiles-credentials.json"
        real.write_text(self.m.CREDS.read_text())
        os.chmod(real, 0o600)
        self.m.CREDS.unlink()
        self.m.CREDS.symlink_to(real)
        self.server.routes["/token"] = reply_json(self.new_tokens())
        self.m.refresh_token()
        self.assertTrue(self.m.CREDS.is_symlink())
        self.assertEqual(json.loads(real.read_text())["claudeAiOauth"]["accessToken"], "new-access-token-abcdef")

    def test_server_keeps_refresh_token_if_not_rotated(self):
        self.write_creds()
        tokens = self.new_tokens()
        del tokens["refresh_token"]
        self.server.routes["/token"] = reply_json(tokens)
        self.m.refresh_token()
        self.assertEqual(json.loads(self.m.CREDS.read_text())["claudeAiOauth"]["refreshToken"], "old-refresh-token-456")

    def test_garbage_token_response_leaves_creds_untouched(self):
        for bad in ({}, {"access_token": ""}, {"access_token": "has space in it"},
                    {"access_token": "line\nbreak-token-1234"}, {"access_token": 12345}):
            self.write_creds()
            before = self.m.CREDS.read_text()
            self.server.routes["/token"] = reply_json(bad)
            with self.assertRaises(ValueError):
                self.m.refresh_token()
            self.assertEqual(self.m.CREDS.read_text(), before, bad)

    def test_rejected_refresh_means_login_expired_and_creds_untouched(self):
        self.write_creds()
        before = self.m.CREDS.read_text()
        self.server.routes["/token"] = reply_json({"error": "invalid_grant"}, status=400)
        with self.assertRaises(self.m.LoginExpired):
            self.m.refresh_token()
        self.assertEqual(self.m.CREDS.read_text(), before)

    def test_absurd_expires_in_is_ignored(self):
        self.write_creds()
        self.server.routes["/token"] = reply_json(self.new_tokens(expires_in=10 ** 12))
        old_exp = json.loads(self.m.CREDS.read_text())["claudeAiOauth"]["expiresAt"]
        self.m.refresh_token()
        self.assertEqual(json.loads(self.m.CREDS.read_text())["claudeAiOauth"]["expiresAt"], old_exp)

    def test_no_request_when_someone_else_already_refreshed(self):
        self.write_creds(expiresAt=int((time.time() + 3600) * 1000))
        oauth = self.m.refresh_token()
        self.assertEqual(oauth["accessToken"], "old-access-token-123")
        self.assertEqual(self.server.requests, [])

    def test_compare_and_swap_keeps_what_claude_code_wrote_meanwhile(self):
        self.write_creds()
        theirs = {"accessToken": "claude-code-access-token", "refreshToken": "claude-code-refresh-token",
                  "expiresAt": int((time.time() + 7200) * 1000)}

        def handler(h, body):
            # Claude Code rotates the tokens while our request is in flight
            data = json.loads(self.m.CREDS.read_text())
            data["claudeAiOauth"].update(theirs)
            self.m.CREDS.write_text(json.dumps(data))
            reply_json(self.new_tokens())(h, body)

        self.server.routes["/token"] = handler
        oauth = self.m.refresh_token()
        self.assertEqual(oauth["accessToken"], "claude-code-access-token")
        saved = json.loads(self.m.CREDS.read_text())["claudeAiOauth"]
        self.assertEqual(saved["refreshToken"], "claude-code-refresh-token")   # not overwritten

    def test_lock_serialises_refreshers(self):
        import fcntl
        self.m.private_dir(self.m.CACHE_DIR)
        fd = os.open(self.m.LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            t0 = time.monotonic()
            with self.assertRaises(RuntimeError):
                with self.m.refresh_lock(timeout=0.5):
                    pass
            self.assertGreaterEqual(time.monotonic() - t0, 0.4)
        finally:
            os.close(fd)
        with self.m.refresh_lock(timeout=0.5):   # free again
            pass

    def test_cache_dir_is_private(self):
        self.write_creds()
        self.server.routes["/token"] = reply_json(self.new_tokens())
        self.m.refresh_token()
        self.assertEqual(stat.S_IMODE(self.m.CACHE_DIR.stat().st_mode), 0o700)


# --------------------------------------------------------------------------

class TestLimits(Base):
    def usage_response(self, **over):
        r = {"limits": [
            {"kind": "session", "percent": 12, "resets_at": "2026-10-17T12:20:00+00:00"},
            {"kind": "weekly_all", "percent": 44.5, "resets_at": "2026-10-21T05:00:00+00:00"},
        ]}
        r.update(over)
        return r

    def test_normalise_hostile_limits(self):
        raw = {"limits": [
            "string", None, 5,
            {"kind": "session", "percent": "50"},                       # text, not a number
            {"kind": "session", "percent": float("nan")},
            {"kind": "weekly_all", "percent": 1e9, "resets_at": "garbage"},
            {"kind": "<b>evil</b>\nkind", "percent": -20, "resets_at": 5},
            {"kind": 42, "percent": 10},
        ]}
        out = self.m.normalise_limits(raw)
        by_key = {i["key"]: i for i in out}
        self.assertEqual(by_key["seven_day"]["percent"], 100.0)          # clamped
        self.assertIsNone(by_key["seven_day"]["resets_at"])              # not a timestamp
        for i in out:
            self.assertNotIn("<", i["key"] + i["label"])
            self.assertNotIn("\n", i["key"] + i["label"])
            self.assertTrue(0 <= i["percent"] <= 100)

    def test_fetch_limits_end_to_end(self):
        self.write_creds(expiresAt=int((time.time() + 3600) * 1000))
        self.server.routes["/usage"] = reply_json(self.usage_response())
        res = self.m.fetch_limits(allow_refresh=True)
        self.assertIsNone(res["error"])
        self.assertEqual([i["key"] for i in res["items"]], ["five_hour", "seven_day"])
        auth = self.server.requests[0][2].get("Authorization")
        self.assertEqual(auth, "Bearer old-access-token-123")

    def test_expired_without_refresh_permission_does_not_touch_network(self):
        self.write_creds()
        res = self.m.fetch_limits(allow_refresh=False)
        self.assertIn("Login abgelaufen", res["error"])
        self.assertEqual(self.server.requests, [])

    def test_expired_with_refresh_uses_new_token(self):
        self.write_creds()
        self.server.routes["/token"] = reply_json(
            {"access_token": "new-access-token-abcdef", "refresh_token": "new-refresh-token-xyz", "expires_in": 3600})
        self.server.routes["/usage"] = reply_json(self.usage_response())
        res = self.m.fetch_limits(allow_refresh=True)
        self.assertIsNone(res["error"])
        usage_req = [r for r in self.server.requests if r[1] == "/usage"][0]
        self.assertEqual(usage_req[2]["Authorization"], "Bearer new-access-token-abcdef")

    def test_http_errors_become_short_messages(self):
        self.write_creds(expiresAt=int((time.time() + 3600) * 1000))
        self.server.routes["/usage"] = reply_json({"error": "x"}, status=500)
        self.assertEqual(self.m.fetch_limits(True)["error"], "HTTP 500")
        os.unlink(self.m.LIMITS_CACHE)
        self.server.routes["/usage"] = reply_json({"error": "x"}, status=401)
        self.assertIn("Login abgelaufen", self.m.fetch_limits(True)["error"])

    def test_missing_creds(self):
        res = self.m.fetch_limits(True)
        self.assertEqual(res["error"], "Kein Claude-Code-Login gefunden")

    def test_creds_without_oauth_block_or_wrong_types(self):
        for content in ('{}', '{"claudeAiOauth": "str"}', '[1]', 'not json',
                        '{"claudeAiOauth": {"accessToken": 5, "expiresAt": "soon"}}'):
            self.m.CREDS.write_text(content)
            res = self.m.fetch_limits(allow_refresh=False)
            self.assertTrue(res["error"], content)
            self.assertEqual(res["items"], [])
            if self.m.LIMITS_CACHE.exists():
                os.unlink(self.m.LIMITS_CACHE)

    def test_error_text_never_contains_the_token(self):
        self.write_creds(expiresAt=int((time.time() + 3600) * 1000))
        self.server.routes["/usage"] = lambda h, b: (h.send_response(200), h.end_headers(), h.wfile.write(b"<<not json>>"))
        res = self.m.fetch_limits(True)
        self.assertTrue(res["error"])
        self.assertNotIn("old-access-token-123", json.dumps(res))

    # --- cache -------------------------------------------------------------

    def cache(self, content, mode=0o600):
        self.m.private_dir(self.m.CACHE_DIR)
        self.m.LIMITS_CACHE.write_text(content if isinstance(content, str) else json.dumps(content))
        os.chmod(self.m.LIMITS_CACHE, mode)

    def test_fresh_cache_is_used_and_sanitised(self):
        self.cache({"fetched": time.time(), "plan": "<i>pro</i>", "error": "<b>x</b>\nyz",
                    "items": [{"key": "k", "label": "<b>L</b>", "percent": 1e9, "resets_at": "no"},
                              "junk", {"percent": "7"}]})
        res = self.m.fetch_limits(True)
        self.assertEqual(self.server.requests, [])
        self.assertEqual(len(res["items"]), 1)
        self.assertEqual(res["items"][0]["percent"], 100.0)
        self.assertNotIn("<", json.dumps(res))

    def test_stale_future_or_broken_cache_is_ignored(self):
        for content in ({"fetched": time.time() - 9999, "items": []},
                        {"fetched": time.time() + 9999, "items": []},       # clock tricks
                        {"fetched": "now", "items": []},
                        {"fetched": time.time(), "items": "nope"},
                        "garbage", "[1]"):
            self.cache(content)
            self.assertIsNone(self.m.read_limits_cache(), content)

    def test_oversized_or_symlinked_cache_is_ignored(self):
        self.cache('{"fetched": %f, "items": [], "pad": "%s"}' % (time.time(), "x" * (self.m.MAX_CACHE_BYTES + 10)))
        self.assertIsNone(self.m.read_limits_cache())
        os.unlink(self.m.LIMITS_CACHE)
        target = self.dir / "elsewhere.json"
        target.write_text(json.dumps({"fetched": time.time(), "items": []}))
        self.m.LIMITS_CACHE.symlink_to(target)
        self.assertIsNone(self.m.read_limits_cache())

    def test_cache_file_is_written_private(self):
        self.write_creds(expiresAt=int((time.time() + 3600) * 1000))
        self.server.routes["/usage"] = reply_json(self.usage_response())
        self.m.fetch_limits(True)
        self.assertEqual(stat.S_IMODE(self.m.LIMITS_CACHE.stat().st_mode), 0o600)


# --------------------------------------------------------------------------

class TestMainProcess(unittest.TestCase):
    """Run the real script as the widget does: python3 -I script."""

    def run_script(self, env_extra, *args):
        env = {"PATH": os.environ.get("PATH", ""), "HOME": env_extra.pop("HOME")}
        env.update(env_extra)
        p = subprocess.run([sys.executable, "-I", str(SCRIPT), *args], env=env,
                           capture_output=True, text=True, timeout=60)
        return p

    def test_always_emits_one_json_object(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.run_script({"HOME": d, "CLAUDE_CONFIG_DIR": d + "/nope", "XDG_CACHE_HOME": d + "/cache"}, "--no-refresh")
            self.assertEqual(p.returncode, 0, p.stderr)
            out = json.loads(p.stdout)
            self.assertEqual(out["limits"]["error"], "Kein Claude-Code-Login gefunden")
            self.assertIsNotNone(out["used"])
            self.assertEqual(p.stderr, "")

    def test_garbage_creds_still_valid_json(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, ".credentials.json").write_text("\x00\x01 not json")
            p = self.run_script({"HOME": d, "CLAUDE_CONFIG_DIR": d, "XDG_CACHE_HOME": d + "/cache"}, "--no-refresh")
            out = json.loads(p.stdout)
            self.assertTrue(out["limits"]["error"])

    def test_cache_dir_permissions_via_real_run(self):
        with tempfile.TemporaryDirectory() as d:
            self.run_script({"HOME": d, "CLAUDE_CONFIG_DIR": d, "XDG_CACHE_HOME": d + "/cache"}, "--no-refresh")
            mode = stat.S_IMODE(os.stat(d + "/cache/claude-usage-widget").st_mode)
            self.assertEqual(mode, 0o700)


if __name__ == "__main__":
    unittest.main(verbosity=2)
