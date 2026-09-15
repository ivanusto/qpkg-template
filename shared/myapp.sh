#!/bin/sh
# shellcheck disable=SC2329 # hooks are called by lib/qpkg-core.sh
######################################################################
# My App QPKG service script
#
# This file is the app-specific layer. Everything generic (waiting for
# Container Station, detached background jobs, idempotent start with
# configuration fingerprints, digest verification, the first-run status
# page, diag) lives in lib/qpkg-core.sh and should not need editing.
#
# To package another app, change the settings block and the hook
# functions below. For each container id listed in CONTAINERS, the core
# expects the variables <ID>_IMAGE and <ID>_CONTAINER_NAME (uppercase id)
# and the functions app_run_<id> and app_fingerprint_<id>.
#
# Usage: myapp.sh {start|stop|restart|status|pull|bgpull|update [--check]|remove|diag}
######################################################################

# ------------------------------------------------------------ settings

QPKG_NAME="MyApp"
DISPLAY_NAME="My App"
SCRIPT_NAME="myapp.sh"
CONF_NAME="myapp.conf"

# Container ids, in start order. Stop runs in reverse.
CONTAINERS="app"
# The container that publishes WEB_PORT (the status page borrows the port
# while images download).
WEB_ID="app"
# Path the status page polls before handing over to the real app. It
# must answer 2xx once the app is ready.
HEALTH_PATH="/"
# Registries checked by diag, besides the ones derived from image refs.
DIAG_HOSTS=""

# ------------------------------------------------------------ hooks

# Defaults for app settings. Called after the .conf file is loaded, so
# only fill in what is unset. Images come from images.lock, not here.
app_defaults() {
    APP_CONTAINER_NAME="${APP_CONTAINER_NAME:-myapp}"
    WEB_PORT="${WEB_PORT:-8190}"
    APP_NAME_FIELD="${APP_NAME_FIELD:-QNAP}"
    APP_EXTRA_ARGS="${APP_EXTRA_ARGS:-}"
    # For an app with state, add a data path and mount it below:
    # APP_DATA_PATH="${APP_DATA_PATH:-$(default_volume)/MyApp/data}"
    # The core creates <ID>_DATA_PATH before the container is created.
}

# Every value that appears on the docker run line below. The core adds
# the image, network and TZ. A change here recreates the container on the
# next start/restart; anything left out is silently ignored by
# "docker start".
app_fingerprint_app() {
    printf '%s\n' "$WEB_PORT" "$APP_NAME_FIELD" "$APP_EXTRA_ARGS"
}

# Create the container (detached). The core handles name and port
# conflicts, logging and fingerprints.
app_run_app() {
    # shellcheck disable=SC2086 # APP_EXTRA_ARGS is word-split on purpose
    "$DOCKER" run -d \
        --name "$APP_CONTAINER_NAME" \
        --network "$NETWORK_NAME" \
        --restart unless-stopped \
        -p "$WEB_PORT":80 \
        -e TZ="$TZ" \
        $APP_EXTRA_ARGS \
        "$APP_IMAGE" --name "$APP_NAME_FIELD"
    # With a data path:  -v "$APP_DATA_PATH":/data
}

# Optional hooks, delete if unused:
#
# app_needs_recreate_app  return 0 to recreate a stopped container that
#                         would otherwise be reused (e.g. GPU self-heal).
# app_run_fallback_app    called with the error output when app_run_app
#                         failed for a reason other than a name or port
#                         conflict (e.g. retry without --gpus).

# Extra rows for the status page: one "label_en|label_zh|value" per line.
app_status_fields() {
    echo "Instance name|實例名稱|$APP_NAME_FIELD"
}

# Extra diag output.
app_diag() {
    echo "APP_NAME_FIELD=$APP_NAME_FIELD"
}

# ------------------------------------------------------------ run

QPKG_ROOT="${QPKG_ROOT_OVERRIDE:-$("${QTS_SBIN:-/sbin}/getcfg" "$QPKG_NAME" Install_Path -f "${QPKG_CONF:-/etc/config/qpkg.conf}")}"
# shellcheck source=lib/qpkg-core.sh
. "$QPKG_ROOT/lib/qpkg-core.sh"
main "$@"
