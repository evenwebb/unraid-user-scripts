#!/bin/bash
#
# clear-plex-codecs.sh
# Delete Plex codec cache (Plex re-downloads as needed).
#
# Description:
#   Frees space under PLEX_CODECS_PATH. Optionally restarts the Plex Docker container after clearing.
#
# Usage:
#   ./clear-plex-codecs.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - PLEX_PATH: Plex appdata root (used when PLEX_CODECS_PATH is empty)
#   - PLEX_CODECS_PATH: codec cache directory (empty = under PLEX_PATH)
#   - PLEX_CONTAINER_NAME: Docker container name (when RESTART_PLEX_CONTAINER=1)
#   - RESTART_PLEX_CONTAINER: 1 = restart Plex after clearing, 0 = no restart (default)
#   - RESTART_ONLY_IF_AUTOSTART: 1 = skip restart if container policy is not always/unless-stopped
#
# Note: Progress and errors print to stdout; Unraid User Scripts shows that in the run window. Optional LOG_FILE also appends a copy to disk.
#
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Plex appdata on the host (Unraid: folder you map to the container's /config)
PLEX_PATH="/mnt/user/appdata/plexmediaserver"

# Codecs folder (leave empty = under PLEX_PATH; set full path only if yours differs)
PLEX_CODECS_PATH=""

# Docker container name for Plex
PLEX_CONTAINER_NAME="plex"

# 1 = restart Plex after clearing codecs, 0 = leave the container running (default)
RESTART_PLEX_CONTAINER="0"

# 1 = only restart if container restart policy is always or unless-stopped
RESTART_ONLY_IF_AUTOSTART="0"

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
}

if [[ -z "$PLEX_CODECS_PATH" ]]; then
    if [[ -z "$PLEX_PATH" ]]; then
        log_err "Set PLEX_PATH (appdata root) or set PLEX_CODECS_PATH to the Codecs directory."
        exit 1
    fi
    PLEX_CODECS_PATH="${PLEX_PATH}/Library/Application Support/Plex Media Server/Codecs"
fi

# Require path to look like a Plex appdata path to reduce accidental misuse
is_safe_plex_codecs_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    [[ "$p" == "/" ]] && return 1
    [[ "$p" == "/mnt" ]] && return 1
    [[ "$p" != *[Pp]lex* ]] && return 1
    return 0
}

restart_plex_container() {
    if [[ "$RESTART_PLEX_CONTAINER" != "1" ]]; then
        return 0
    fi
    if [[ -z "$PLEX_CONTAINER_NAME" ]]; then
        log_err "RESTART_PLEX_CONTAINER is 1 but PLEX_CONTAINER_NAME is empty."
        return 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        log_err "docker is required to restart Plex but was not found."
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        log_err "Docker daemon not available (is Docker started in Unraid?)."
        return 1
    fi
    if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qxF "$PLEX_CONTAINER_NAME"; then
        log_err "Plex container '$PLEX_CONTAINER_NAME' was not found. Check PLEX_CONTAINER_NAME in this script."
        return 1
    fi

    if [[ "$RESTART_ONLY_IF_AUTOSTART" == "1" ]]; then
        local policy
        policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$PLEX_CONTAINER_NAME" 2>/dev/null || echo "no")
        if [[ "$policy" != "always" && "$policy" != "unless-stopped" ]]; then
            log "Skipping Plex restart: container restart policy is '$policy' (RESTART_ONLY_IF_AUTOSTART=1)."
            return 0
        fi
    fi

    log "Restarting Plex container: $PLEX_CONTAINER_NAME"
    if docker restart "$PLEX_CONTAINER_NAME" >/dev/null; then
        log "Plex container restarted."
        return 0
    fi
    log_err "docker restart failed for $PLEX_CONTAINER_NAME"
    return 1
}

main() {
    local clear_rc=0 restart_rc=0

    if [[ "$RESTART_PLEX_CONTAINER" != "0" && "$RESTART_PLEX_CONTAINER" != "1" ]]; then
        log_err "RESTART_PLEX_CONTAINER must be 0 or 1."
        return 1
    fi
    if [[ "$RESTART_ONLY_IF_AUTOSTART" != "0" && "$RESTART_ONLY_IF_AUTOSTART" != "1" ]]; then
        log_err "RESTART_ONLY_IF_AUTOSTART must be 0 or 1."
        return 1
    fi

    if ! is_safe_plex_codecs_path "$PLEX_CODECS_PATH"; then
        log_err "Refusing to delete: path does not look like a Plex path (must contain 'plex'). Set PLEX_PATH / PLEX_CODECS_PATH correctly."
        return 1
    fi
    if [[ ! -d "$PLEX_CODECS_PATH" ]]; then
        log "Directory does not exist (nothing to do): $PLEX_CODECS_PATH"
    else
        log "Deleting all contents inside: $PLEX_CODECS_PATH"
        local found=0 fail=0
        shopt -s nullglob
        local items=()
        for g in "$PLEX_CODECS_PATH"/* "$PLEX_CODECS_PATH"/.[!.]* "$PLEX_CODECS_PATH"/..?*; do
            items+=("$g")
        done
        shopt -u nullglob
        found=${#items[@]}
        if [[ $found -eq 0 ]]; then
            log "No items found to delete in $PLEX_CODECS_PATH"
        else
            local item
            for item in "${items[@]}"; do
                rm -rf "$item" 2>/dev/null || { log_err "Failed to delete: $item"; fail=1; }
            done
            if [[ $fail -eq 0 ]]; then
                log "Deletion complete ($found item(s) removed)."
            else
                log_err "Deletion completed with errors; some items may not have been removed."
                clear_rc=1
            fi
        fi
    fi

    if [[ $clear_rc -eq 0 ]]; then
        restart_plex_container || restart_rc=$?
    else
        log "Skipping Plex restart because codec deletion did not complete cleanly."
    fi

    if [[ $clear_rc -ne 0 || $restart_rc -ne 0 ]]; then
        return 1
    fi
    return 0
}

main "$@"
