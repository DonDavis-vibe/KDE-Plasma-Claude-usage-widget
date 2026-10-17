#!/usr/bin/env bash
# Tests for install.sh: normal install/update plus simulated failures.
# Everything happens in a throw-away XDG_DATA_HOME; the real widget is never touched.
#
# Run:  bash tests/test_install.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL_KPT="$(command -v kpackagetool6)" || { echo "kpackagetool6 fehlt"; exit 2; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ID=org.local.claudeusage
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# A copy of the project so tests can break the package without harming the source
new_case() {
    CASE="$TMP/$1"; mkdir -p "$CASE/data" "$CASE/bin"
    cp -a "$ROOT/install.sh" "$ROOT/package" "$CASE/"
    export XDG_DATA_HOME="$CASE/data"
    TARGET="$XDG_DATA_HOME/plasma/plasmoids/$ID"
}

# Fake kpackagetool6: delegates to the real one, except for "-u" where FAKE_MODE decides.
cat > "$TMP/fake-kpackagetool6" <<EOF
#!/usr/bin/env bash
REAL="$REAL_KPT"
TARGET="\$XDG_DATA_HOME/plasma/plasmoids/$ID"
if [[ " \$* " == *" -u "* ]]; then
    case "\${FAKE_MODE:-}" in
        abort)   rm -rf "\$TARGET"; echo "simulated abort" >&2; exit 1 ;;
        hang)    rm -rf "\$TARGET"; sleep 30; exit 1 ;;
        corrupt) "\$REAL" "\$@"; echo "junk" >> "\$TARGET/contents/ui/main.qml"; exit 0 ;;
    esac
fi
exec "\$REAL" "\$@"
EOF
chmod +x "$TMP/fake-kpackagetool6"
use_fake() { ln -sf "$TMP/fake-kpackagetool6" "$CASE/bin/kpackagetool6"; export PATH="$CASE/bin:$ORIG_PATH"; }
ORIG_PATH="$PATH"
hash_dir() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1); }

echo "1. fresh install"
new_case fresh
bash "$CASE/install.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit 0"                        '[ $rc -eq 0 ]'
check "widget is installed"           '[ -f "$TARGET/contents/ui/main.qml" ]'
check "installed == package"          'diff -rq "$CASE/package" "$TARGET" >/dev/null'

echo "2. update over an existing install"
echo "// changed" >> "$CASE/package/contents/ui/main.qml"
bash "$CASE/install.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit 0"                        '[ $rc -eq 0 ]'
check "new file content installed"    'grep -q "// changed" "$TARGET/contents/ui/main.qml"'
check "says 'aktualisiert'"           'grep -q aktualisiert "$CASE/out.log"'

echo "3. kpackagetool aborts in the middle of the update -> old widget comes back"
new_case abort; PATH="$ORIG_PATH"
bash "$CASE/install.sh" >/dev/null 2>&1
before="$(hash_dir "$TARGET")"
echo "// new version" >> "$CASE/package/contents/ui/main.qml"
use_fake; FAKE_MODE=abort bash "$CASE/install.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit != 0"                     '[ $rc -ne 0 ]'
check "widget still installed"        '[ -f "$TARGET/contents/ui/main.qml" ]'
check "identical to the old install"  '[ "$(hash_dir "$TARGET")" = "$before" ]'
check "tells the user about rollback" 'grep -q "wiederhergestellt" "$CASE/out.log"'

echo "4. Ctrl-C in the middle of the update -> old widget comes back"
new_case sigint; PATH="$ORIG_PATH"
bash "$CASE/install.sh" >/dev/null 2>&1
before="$(hash_dir "$TARGET")"
echo "// new version" >> "$CASE/package/contents/ui/main.qml"
use_fake
FAKE_MODE=hang timeout -s INT 3 bash "$CASE/install.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit != 0"                     '[ $rc -ne 0 ]'
check "widget still installed"        '[ -f "$TARGET/contents/ui/main.qml" ]'
check "identical to the old install"  '[ "$(hash_dir "$TARGET")" = "$before" ]'

echo "5. broken package is refused before anything is touched"
new_case broken; PATH="$ORIG_PATH"
bash "$CASE/install.sh" >/dev/null 2>&1
before="$(hash_dir "$TARGET")"
echo "def broken(:" >> "$CASE/package/contents/code/claude_usage.py"
bash "$CASE/install.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit != 0"                     '[ $rc -ne 0 ]'
check "installed widget untouched"    '[ "$(hash_dir "$TARGET")" = "$before" ]'
check "no kpackagetool run (no 'aktualisiert')" '! grep -q aktualisiert "$CASE/out.log"'

echo "6. wrong plugin id is refused"
new_case wrongid; PATH="$ORIG_PATH"
sed -i 's/org.local.claudeusage/org.evil.other/' "$CASE/package/metadata.json"
bash "$CASE/install.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit != 0"                     '[ $rc -ne 0 ]'
check "nothing installed"             '[ ! -e "$TARGET" ]'

echo "7. incomplete package is refused"
new_case incomplete; PATH="$ORIG_PATH"
rm "$CASE/package/contents/ui/main.qml"
bash "$CASE/install.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit != 0"                     '[ $rc -ne 0 ]'
check "nothing installed"             '[ ! -e "$TARGET" ]'

echo "8. install result differs from the package -> rollback"
new_case corrupt; PATH="$ORIG_PATH"
bash "$CASE/install.sh" >/dev/null 2>&1
before="$(hash_dir "$TARGET")"
echo "// new version" >> "$CASE/package/contents/ui/main.qml"
use_fake; FAKE_MODE=corrupt bash "$CASE/install.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit != 0"                     '[ $rc -ne 0 ]'
check "identical to the old install"  '[ "$(hash_dir "$TARGET")" = "$before" ]'

echo "9. uninstall removes the widget and only our own cache"
new_case uninst; PATH="$ORIG_PATH"
cp -a "$ROOT/uninstall.sh" "$CASE/"
bash "$CASE/install.sh" >/dev/null 2>&1
export XDG_CACHE_HOME="$CASE/cache"; mkdir -p "$XDG_CACHE_HOME/claude-usage-widget" "$XDG_CACHE_HOME/other"
echo x > "$XDG_CACHE_HOME/claude-usage-widget/limits.json"; echo keep > "$XDG_CACHE_HOME/other/file"
bash "$CASE/uninstall.sh" >"$CASE/out.log" 2>&1; rc=$?
check "exit 0"                        '[ $rc -eq 0 ]'
check "widget removed"                '[ ! -e "$TARGET" ]'
check "own cache removed"             '[ ! -e "$XDG_CACHE_HOME/claude-usage-widget" ]'
check "other cache untouched"         '[ -f "$XDG_CACHE_HOME/other/file" ]'
bash "$CASE/uninstall.sh" >"$CASE/out.log" 2>&1; rc=$?
check "second run is harmless"        '[ $rc -eq 0 ] && grep -q "nicht installiert" "$CASE/out.log"'
mkdir -p "$CASE/elsewhere"; echo precious > "$CASE/elsewhere/f"; ln -s "$CASE/elsewhere" "$XDG_CACHE_HOME/claude-usage-widget"
bash "$CASE/uninstall.sh" >/dev/null 2>&1
check "a symlinked cache dir is not followed" '[ -f "$CASE/elsewhere/f" ]'
unset XDG_CACHE_HOME

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
