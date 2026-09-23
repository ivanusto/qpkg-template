#!/bin/sh
# shellcheck disable=SC2016,SC2034 # check() evals its single-quoted condition later
# Lifecycle test against the local docker daemon, with QTS commands
# stubbed out. Uses its own container, network and port names so it does
# not touch anything else on the machine. The demo image is removed first
# so the background download path is exercised.
#
# Usage: tests/lifecycle.sh        (TEST_PORT=18190 by default)
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT="${TEST_PORT:-18190}"
PORT2=$((PORT + 1))
PORT3=$((PORT + 2))
PREFIX="qpkgtpl-test"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/qpkg-template-test.XXXXXX")
PASS=0
FAIL=0

export QPKG_ROOT_OVERRIDE="$WORK/root"
export QPKG_CONF="$WORK/qpkg.conf"
export QTS_SBIN="$ROOT/tests/stubs"
export TEST_EVENT_LOG="$WORK/event.log"

SCRIPT=$(sed -n 's/^SCRIPT_NAME="\(.*\)"/\1/p' "$ROOT"/shared/*.sh | head -n 1)
QPKG_NAME=$(sed -n 's/^QPKG_NAME="\(.*\)"/\1/p' "$ROOT/qpkg.cfg")
APP="$QPKG_ROOT_OVERRIDE/$SCRIPT"
CONF_FILE="$QPKG_ROOT_OVERRIDE/$(sed -n 's/^CONF_NAME="\(.*\)"/\1/p' "$ROOT"/shared/*.sh | head -n 1)"
IMAGE=$(sed -n 's/^APP_IMAGE=//p' "$ROOT/shared/images.lock")
# A second pinned image for the "pin moved" scenario; never present at start.
ALT_IMAGE="traefik/whoami:v1.11.0@sha256:200689790a0a0ea48ca45992e0450bc26ccab5307375b41c84dfc4f2475937ab"
C_APP="$PREFIX-app"
C_EXTRA="$PREFIX-extra"
C_BLOCK="$PREFIX-blocker"
NET="$PREFIX-net"

ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

state() { sed -n 's/.*"state": "\([^"]*\)".*/\1/p' "$QPKG_ROOT_OVERRIDE/web/status.json" 2>/dev/null; }
created() { docker inspect -f '{{.Created}}' "$1" 2>/dev/null; }
http_ok() { curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$1$2"; }

wait_for() {
    # $1 = description, $2 = condition, $3 = timeout seconds
    W=0
    while ! eval "$2"; do
        W=$((W + 1))
        [ "$W" -ge "$3" ] && { bad "$1 (timed out after $3 s)"; return 1; }
        sleep 1
    done
    ok "$1"
}

cleanup() {
    docker rm -f "$C_APP" "$C_APP-landing" "$C_EXTRA" "$C_BLOCK" >/dev/null 2>&1
    docker network rm "$NET" >/dev/null 2>&1
    # The docker load section leaves a bare tag that cannot be removed
    # while its container runs; drop it once the container is gone.
    docker rmi "${IMAGE%@*}" >/dev/null 2>&1
    docker rmi "$ALT_IMAGE" "${ALT_IMAGE%@*}" >/dev/null 2>&1
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

echo "== setup ($WORK)"
cleanup
mkdir -p "$WORK" "$QPKG_ROOT_OVERRIDE"
cp -R "$ROOT/shared/." "$QPKG_ROOT_OVERRIDE/"
chmod +x "$APP"
cat > "$QPKG_CONF" <<EOF
[$QPKG_NAME]
Name = $QPKG_NAME
Version = test
Enable = TRUE
Install_Path = $QPKG_ROOT_OVERRIDE
Web_Port = 8190
EOF
cp "$QPKG_ROOT_OVERRIDE"/*.conf.default "$CONF_FILE"
cat >> "$CONF_FILE" <<EOF
APP_CONTAINER_NAME="$C_APP"
NETWORK_NAME="$NET"
WEB_PORT="$PORT"
TZ="UTC"
STOP_TIMEOUT="1"
PULL_RETRY_DELAY="1"
EOF
# Remove the bare tag as well: a leftover repository:tag without a repo
# digest (e.g. from an earlier docker load) would stand in for the pin.
docker rmi "$IMAGE" "${IMAGE%@*}" "$ALT_IMAGE" "${ALT_IMAGE%@*}" >/dev/null 2>&1
docker image inspect "$IMAGE" >/dev/null 2>&1 && echo "  note: $IMAGE still present (in use elsewhere); download path not exercised"

echo "== 1. first start downloads in the background"
"$APP" start 2>/dev/null
check "start returns with downloading-image or running" '[ "$(state)" = downloading-image ] || [ "$(state)" = running ]'
if [ "$(state)" = downloading-image ]; then
    wait_for "status page answers on port $PORT" 'http_ok "$PORT" /status.json' 30
fi
wait_for "state becomes running" '[ "$(state)" = running ]' 180
wait_for "app answers on port $PORT" 'http_ok "$PORT" /' 30
check "status page container is gone" '! docker inspect "$C_APP-landing" >/dev/null 2>&1'
check "status.json reports the pin as verified" 'grep -q "\"digest\": \"pinned-ok\"" "$QPKG_ROOT_OVERRIDE/web/status.json"'
check "fingerprint recorded" '[ -s "$QPKG_ROOT_OVERRIDE/.conf-$C_APP" ]'
check "App Center port synced" '[ "$("$QTS_SBIN/getcfg" "$QPKG_NAME" Web_Port -f "$QPKG_CONF")" = "$PORT" ]'
check "status exits 0" '"$APP" status >/dev/null'

echo "== 2. restart without changes reuses the container"
C1=$(created "$C_APP")
"$APP" restart 2>/dev/null
check "running after restart" 'docker inspect -f "{{.State.Running}}" "$C_APP" | grep -q true'
check "container not recreated" '[ "$(created "$C_APP")" = "$C1" ]'

echo "== 3. changed setting recreates the container"
sed -i "s/^WEB_PORT=.*/WEB_PORT=\"$PORT2\"/" "$CONF_FILE"
"$APP" restart 2>/dev/null
check "container recreated" '[ "$(created "$C_APP")" != "$C1" ]'
wait_for "app answers on new port $PORT2" 'http_ok "$PORT2" /' 30
check "App Center port follows" '[ "$("$QTS_SBIN/getcfg" "$QPKG_NAME" Web_Port -f "$QPKG_CONF")" = "$PORT2" ]'

echo "== 4. update with a pinned digest changes nothing"
C2=$(created "$C_APP")
"$APP" update 2>/dev/null
RC=$?
check "update exits 0" '[ "$RC" -eq 0 ]'
check "container not recreated by update" '[ "$(created "$C_APP")" = "$C2" ]'
OUT=$("$APP" update --check 2>&1)
check "update --check reports the pin" 'echo "$OUT" | grep -q "pinned"'
check "update --check leaves the container alone" '[ "$(created "$C_APP")" = "$C2" ]'

echo "== 4b. pin moved while the container exists: download in the background"
# An upgrade that ships a new pin: the container exists but must be
# recreated from an image that is not here yet. start must not pull it
# in the foreground (App Center would wait for the whole download), and
# must not take the app down either: the previous version keeps serving.
"$APP" stop 2>/dev/null
echo "APP_IMAGE=\"$ALT_IMAGE\"" >> "$CONF_FILE"
T0=$(date +%s)
"$APP" start 2>/dev/null
T1=$(date +%s)
check "start returns within 10 s" '[ $((T1 - T0)) -le 10 ]'
check "start keeps the previous version serving" '[ "$(state)" = updating ] || [ "$(state)" = running ]'
check "no status page over the running app" '! docker inspect "$C_APP-landing" >/dev/null 2>&1'
wait_for "state becomes running" '[ "$(state)" = running ]' 180
check "container recreated from the new pin" '[ "$(docker inspect -f "{{.Config.Image}}" "$C_APP")" = "$ALT_IMAGE" ]'
sed -i '/^APP_IMAGE=/d' "$CONF_FILE"
"$APP" restart 2>/dev/null
check "back on the original pin" '[ "$(docker inspect -f "{{.Config.Image}}" "$C_APP")" = "$IMAGE" ]'

echo "== 4c. a failed download of a new pin keeps the previous version"
# A registry CDN can stall on a fresh release for hours. A digest that
# does not exist fails the same way, only faster.
C4=$(created "$C_APP")
echo "APP_IMAGE=\"traefik/whoami:v1.10.9@sha256:$(printf '%064d' 0)\"" >> "$CONF_FILE"
"$APP" restart 2>/dev/null
check "restart goes to updating" '[ "$(state)" = updating ]'
check "app still answers while downloading" 'http_ok "$PORT2" /'
wait_for "failed download ends in running" '[ "$(state)" = running ]' 60
check "failure logged as a warning" '[ "$(grep -c "still running the previous version" "$QPKG_ROOT_OVERRIDE"/logs/*.log | awk -F: "{s += \$NF} END {print s + 0}")" -ge 1 ]'
check "container not recreated" '[ "$(created "$C_APP")" = "$C4" ]'
check "status exits 0" '"$APP" status >/dev/null'
# A pull left by an older version is still running: the new job waits
# for it, then makes its own attempt.
sleep 12 &
echo $! > "$QPKG_ROOT_OVERRIDE/logs/pull.pid"
"$APP" restart 2>/dev/null
sleep 5
check "new job waits for the earlier pull" '[ "$(state)" = updating ]'
wait_for "then makes its own attempt" '[ "$(grep -c "still running the previous version" "$QPKG_ROOT_OVERRIDE"/logs/*.log | awk -F: "{s += \$NF} END {print s + 0}")" -ge 2 ]' 60
check "app still answers" 'http_ok "$PORT2" /'
sed -i '/^APP_IMAGE=/d' "$CONF_FILE"
"$APP" restart 2>/dev/null

echo "== 5. floating tag is flagged"
echo "APP_IMAGE=\"${IMAGE%@*}\"" >> "$CONF_FILE"
"$APP" restart 2>/dev/null
check "status.json reports unpinned" 'grep -q "\"digest\": \"unpinned\"" "$QPKG_ROOT_OVERRIDE/web/status.json"'
check "warning logged" 'grep -q "floating tag" "$QPKG_ROOT_OVERRIDE/logs/"*.log'
sed -i '/^APP_IMAGE=/d' "$CONF_FILE"
"$APP" restart 2>/dev/null

echo "== 6. image imported with docker load (isolated network)"
TAGREF="${IMAGE%@*}"
"$APP" remove 2>/dev/null
docker tag "$IMAGE" "$TAGREF"
docker save -o "$WORK/image.tar" "$TAGREF"
docker rmi -f "$IMAGE" "$TAGREF" >/dev/null 2>&1
check "pinned reference gone before import" '! docker image inspect "$IMAGE" >/dev/null 2>&1'
docker load -i "$WORK/image.tar" >/dev/null
check "imported image has no repo digest" '[ -z "$(docker image inspect -f "{{range .RepoDigests}}{{.}}{{end}}" "$TAGREF")" ]'
"$APP" start 2>/dev/null
check "starts without downloading" '[ "$(state)" = running ]'
check "container runs" 'docker inspect -f "{{.State.Running}}" "$C_APP" 2>/dev/null | grep -q true'
check "status.json reports unverifiable" 'grep -q "\"digest\": \"unverifiable\"" "$QPKG_ROOT_OVERRIDE/web/status.json"'
check "import warning logged" 'grep -q "cannot be verified" "$QPKG_ROOT_OVERRIDE/logs/"*.log'
C3=$(created "$C_APP")
docker pull -q "$IMAGE" >/dev/null
"$APP" restart 2>/dev/null
check "after pulling the pin, status is pinned-ok" 'grep -q "\"digest\": \"pinned-ok\"" "$QPKG_ROOT_OVERRIDE/web/status.json"'
check "same image, container not recreated" '[ "$(created "$C_APP")" = "$C3" ]'
docker rmi "$TAGREF" >/dev/null 2>&1

echo "== 7. optional container that can be switched off"
# Turn the demo into a two-container app: "extra" starts first, may fail
# without failing the app, and is off unless EXTRA_ENABLED=true.
sed -i 's/^CONTAINERS="app"/CONTAINERS="extra app"/; s/^OPTIONAL_CONTAINERS=""/OPTIONAL_CONTAINERS="extra"/' "$APP"
sed -i '/^# -* run$/i\
app_enabled_extra() { [ "$EXTRA_ENABLED" = "true" ]; }\
app_fingerprint_extra() { echo "$EXTRA_PORT"; }\
app_run_extra() {\
    "$DOCKER" run -d --name "$EXTRA_CONTAINER_NAME" --network "$NETWORK_NAME" -p "$EXTRA_PORT":80 "$EXTRA_IMAGE"\
}\
' "$APP"
cat >> "$CONF_FILE" <<EOF
EXTRA_IMAGE="$IMAGE"
EXTRA_CONTAINER_NAME="$C_EXTRA"
EXTRA_PORT="$PORT3"
EXTRA_ENABLED="false"
EOF
"$APP" restart 2>/dev/null
check "switched off: app running" '[ "$(state)" = running ]'
check "switched off: container not created" '! docker inspect "$C_EXTRA" >/dev/null 2>&1'
check "switched off: not on the status page" '! grep -q "\"id\": \"extra\"" "$QPKG_ROOT_OVERRIDE/web/status.json"'
check "switched off: status exits 0" '"$APP" status >/dev/null'

docker run -d --name "$C_BLOCK" -p "$PORT3":80 "$IMAGE" >/dev/null
sed -i 's/^EXTRA_ENABLED=.*/EXTRA_ENABLED="true"/' "$CONF_FILE"
"$APP" restart 2>/dev/null
check "optional fails: app still running" '[ "$(state)" = running ]'
check "optional fails: status exits 0" '"$APP" status >/dev/null'
check "optional fails: warning logged" 'grep -q "Optional container .extra. did not start" "$QPKG_ROOT_OVERRIDE/logs/"*.log'
check "optional fails: listed as optional, not running" 'grep -q "\"id\": \"extra\".*\"running\": false, \"optional\": true" "$QPKG_ROOT_OVERRIDE/web/status.json"'

docker rm -f "$C_BLOCK" >/dev/null 2>&1
"$APP" restart 2>/dev/null
check "port freed: optional container runs" 'docker inspect -f "{{.State.Running}}" "$C_EXTRA" 2>/dev/null | grep -q true'

sed -i 's/^EXTRA_ENABLED=.*/EXTRA_ENABLED="false"/' "$CONF_FILE"
"$APP" start 2>/dev/null
check "switched off again: container stopped" 'docker inspect -f "{{.State.Running}}" "$C_EXTRA" 2>/dev/null | grep -q false'
check "switched off again: logged" 'grep -q "Stopped .extra. because it is switched off" "$QPKG_ROOT_OVERRIDE/logs/"*.log'
check "switched off again: app running" '"$APP" status >/dev/null'

echo "== 8. diag"
OUT=$("$APP" diag 2>&1)
RC=$?
check "diag exits 0" '[ "$RC" -eq 0 ]'
for S in package docker "registry DNS" images containers network configuration app; do
    check "diag has section '$S'" 'echo "$OUT" | grep -q -- "--- $S ---"'
done
check "diag marks the switched-off container" 'echo "$OUT" | grep -q "^extra: .*disabled"'

echo "== 9. stop and remove"
"$APP" stop 2>/dev/null
check "stopped" '! "$APP" status >/dev/null'
check "state stopped" '[ "$(state)" = stopped ]'
"$APP" remove 2>/dev/null
check "container removed" '! docker inspect "$C_APP" >/dev/null 2>&1'
check "switched-off container removed too" '! docker inspect "$C_EXTRA" >/dev/null 2>&1'
check "network removed" '! docker network inspect "$NET" >/dev/null 2>&1'
check "fingerprint removed" '[ ! -f "$QPKG_ROOT_OVERRIDE/.conf-$C_APP" ]'
check "configuration kept" '[ -f "$CONF_FILE" ]'

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
