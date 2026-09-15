#!/bin/sh
# Turn the template into your app: renames MyApp / myapp / "My App"
# in file names and file contents. Run once, right after creating your
# repository from the template.
#
# Usage: scripts/new-app.sh <QpkgName> "<Display Name>" <slug>
#   e.g. scripts/new-app.sh ChangeDetectionQnap "changedetection.io" changedetection
set -eu

usage() {
    echo "Usage: $0 <QpkgName> \"<Display Name>\" <slug>" >&2
    echo "  QpkgName  letters and digits, starts with a letter (App Center internal name)" >&2
    echo "  slug      lowercase letters, digits and dashes (script and container names)" >&2
    exit 2
}

[ $# -eq 3 ] || usage
NAME="$1"
DISPLAY="$2"
SLUG="$3"

echo "$NAME" | grep -Eq '^[A-Za-z][A-Za-z0-9]*$' || usage
echo "$SLUG" | grep -Eq '^[a-z][a-z0-9-]*$' || usage
case "$DISPLAY" in *'|'*|*\\*|*'&'*) echo "Display name must not contain | \\ or &" >&2; exit 2 ;; esac
[ "$NAME" != "MyApp" ] || { echo "Pick a name other than MyApp." >&2; exit 2; }

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

[ -f shared/myapp.sh ] || { echo "shared/myapp.sh not found; already renamed?" >&2; exit 1; }

move() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git ls-files --error-unmatch "$1" >/dev/null 2>&1; then
        git mv "$1" "$2"
    else
        mv "$1" "$2"
    fi
}

move shared/myapp.sh "shared/$SLUG.sh"
move shared/myapp.conf.default "shared/$SLUG.conf.default"
for F in icons/MyApp*.gif; do
    move "$F" "icons/$NAME${F#icons/MyApp}"
done

# Contents. README files describe the template itself and are left for
# you to rewrite; this script and its test keep the placeholder names.
find . -type f \
    ! -path './.git/*' \
    ! -name 'README*' \
    ! -name 'LICENSE' \
    ! -name '*.gif' \
    ! -path './scripts/new-app.sh' \
    ! -path './tests/new-app.sh' \
    ! -path './build/*' \
    -print | while IFS= read -r F; do
        grep -q 'MyApp\|myapp\|My App' "$F" 2>/dev/null || continue
        sed -i \
            -e "s|My App|$DISPLAY|g" \
            -e "s|MyApp|$NAME|g" \
            -e "s|myapp|$SLUG|g" \
            "$F"
        echo "updated $F"
    done

echo
echo "Done. Next:"
echo "  1. shared/$SLUG.sh: CONTAINERS, the app_* hooks, HEALTH_PATH"
echo "  2. shared/images.lock: scripts/pin-images.sh APP_IMAGE=<repository>:<tag>"
echo "  3. qpkg.cfg: QPKG_VER, QPKG_WEB_PORT, QPKG_SUMMARY; icons/"
echo "  4. make test && make"
