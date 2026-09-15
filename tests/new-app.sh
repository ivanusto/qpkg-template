#!/bin/sh
# shellcheck disable=SC2016 # check() evals its single-quoted condition later
# scripts/new-app.sh on a scratch copy: renamed files exist, no
# placeholder names remain outside README, and the pins still check out.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/qpkg-template-newapp.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
FAIL=0

tar -C "$ROOT" --exclude=.git --exclude=build -cf - . | tar -C "$WORK" -xf -
cd "$WORK" || exit 1

check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; FAIL=1; fi; }

sh scripts/new-app.sh DemoQnap "Demo App" demo >/dev/null
check "service script renamed" '[ -f shared/demo.sh ] && [ ! -f shared/myapp.sh ]'
check "conf template renamed" '[ -f shared/demo.conf.default ]'
check "icons renamed" '[ -f icons/DemoQnap.gif ] && [ -f icons/DemoQnap_80.gif ] && [ -f icons/DemoQnap_gray.gif ]'
check "qpkg.cfg updated" 'grep -q "^QPKG_NAME=\"DemoQnap\"" qpkg.cfg && grep -q "^QPKG_SERVICE_PROGRAM=\"demo.sh\"" qpkg.cfg'
check "package_routines updated" 'grep -q "demo.sh remove" package_routines'
LEFT=$(grep -rIl 'MyApp\|myapp\|My App' . --exclude='README*' --exclude=new-app.sh 2>/dev/null)
check "no placeholder names left" '[ -z "$LEFT" ]'
[ -z "$LEFT" ] || echo "$LEFT" | sed 's/^/       /'
check "pins still valid" 'sh scripts/check-pins.sh >/dev/null'
check "second run refuses" '! sh scripts/new-app.sh Other "Other" other >/dev/null 2>&1'

exit "$FAIL"
