#!/usr/bin/env bash
# Removes the "Claude Usage" plasmoid and its small cache for the current user.
# Never touches your Claude Code files (~/.claude). Does not restart Plasma.
set -euo pipefail

ID=org.local.claudeusage
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage-widget"

command -v kpackagetool6 >/dev/null || { echo "Fehler: kpackagetool6 fehlt." >&2; exit 1; }

if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$ID"; then
    kpackagetool6 -t Plasma/Applet -r "$ID"
else
    echo "Das Widget ist nicht installiert."
fi

# only our own cache directory, and only if it really is one (no symlink games)
if [ -d "$CACHE" ] && [ ! -L "$CACHE" ]; then
    rm -rf -- "$CACHE"
    echo "Cache entfernt: $CACHE"
fi

cat <<'EOF'

Entfernt. Falls das Widget noch auf dem Desktop oder im Panel liegt, entferne es dort
und lade Plasma neu:

  systemctl --user restart plasma-plasmashell
EOF
