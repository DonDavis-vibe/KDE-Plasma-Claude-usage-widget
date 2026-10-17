#!/usr/bin/env bash
# Installs or updates ONLY the "Claude-Verbrauch" plasmoid for the current user.
# Does not touch the wallpaper, does not restart Plasma, keeps the widget's settings.
#
# Safe update: `kpackagetool6 -u` removes the old widget before it installs the new
# one, so an abort in between would leave nothing behind. This script therefore
#   1. checks the package before touching anything,
#   2. keeps a copy of the installed widget,
#   3. verifies the result and rolls back to the copy on any failure (also on Ctrl-C).
set -euo pipefail
umask 022
cd "$(dirname "$0")"

ID=org.local.claudeusage
PKG=package
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
TARGET="$DATA/plasma/plasmoids/$ID"

die() { echo "Fehler: $*" >&2; exit 1; }

command -v kpackagetool6 >/dev/null || die "kpackagetool6 fehlt – dieses Widget braucht KDE Plasma 6."
command -v python3       >/dev/null || die "python3 fehlt (wird vom Widget gebraucht)."

# --- 1. check the package before touching the installed widget ---------------
[ -f "$PKG/metadata.json" ] && [ -f "$PKG/contents/ui/main.qml" ] \
    && [ -f "$PKG/contents/code/claude_usage.py" ] || die "Paket unvollständig ($PKG/)."

python3 -I - "$PKG" "$ID" <<'PY' || die "Paketprüfung fehlgeschlagen."
import ast, json, sys
pkg, want = sys.argv[1], sys.argv[2]
meta = json.load(open(f"{pkg}/metadata.json", encoding="utf-8"))
assert meta["KPlugin"]["Id"] == want, "falsche Plugin-Id"
ast.parse(open(f"{pkg}/contents/code/claude_usage.py", encoding="utf-8").read())  # syntax only, nothing runs
PY

# --- 2. keep a copy of what is installed now ---------------------------------
BACKUP="$(mktemp -d)"
UPDATING=0
DONE=0

restore() {
    rm -rf "$TARGET"
    if [ -d "$BACKUP/old" ]; then
        cp -a "$BACKUP/old" "$TARGET"
        echo "Rückgängig gemacht: das vorherige Widget wurde wiederhergestellt." >&2
    fi
}
cleanup() {
    code=$?
    if [ "$UPDATING" = 1 ] && [ "$DONE" != 1 ]; then
        restore
    fi
    rm -rf "$BACKUP"
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$ID"; then
    [ -d "$TARGET" ] && cp -a "$TARGET" "$BACKUP/old"
    echo "== Vorhandenes Widget wird aktualisiert"
    UPDATING=1
    kpackagetool6 -t Plasma/Applet -u "$PKG"
else
    echo "== Widget wird neu installiert"
    UPDATING=1
    kpackagetool6 -t Plasma/Applet -i "$PKG"
fi

# --- 3. verify the result ----------------------------------------------------
[ -f "$TARGET/contents/ui/main.qml" ] || die "Installation unvollständig: $TARGET"
diff -rq "$PKG" "$TARGET" >/dev/null || die "Installierte Dateien weichen vom Paket ab."
DONE=1

cat <<'EOF'

Fertig. Damit Plasma die neue Version lädt, muss es einmal neu starten
(Taskleiste und Desktop flackern dabei kurz):

  systemctl --user restart plasma-plasmashell

Danach: Rechtsklick auf das Widget -> "Claude-Verbrauch einrichten".
EOF
