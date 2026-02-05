#!/bin/bash
#
# clear-movies-download-folder.sh
# Empties the movies download directory and optionally sends a notification
#
# Description:
#   Counts and measures the movies download folder, deletes all contents,
#   then prints a summary. Optionally sends a Pushover notification with
#   the summary (configure PUSHOVER_* below).
#
# Usage:
#   ./clear-movies-download-folder.sh
#
# Configuration:
#   - DIR_PATH: Path to the movies download folder to clear
#   - Optional: PUSHOVER_USER_KEY and PUSHOVER_APP_TOKEN for notifications
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Movies download directory - EDIT FOR YOUR SETUP
DIR_PATH="/mnt/user/downloads/complete/movies"

# Optional: Pushover (leave empty to skip notification)
PUSHOVER_USER_KEY=""
PUSHOVER_APP_TOKEN=""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

send_pushover() {
    local title="$1"
    local message="$2"
    [[ -z "$PUSHOVER_APP_TOKEN" || -z "$PUSHOVER_USER_KEY" ]] && return 0
    if ! command -v curl >/dev/null 2>&1; then
        log "Warning: curl not found, Pushover notification skipped"
        return 0
    fi
    curl -s --form-string "token=$PUSHOVER_APP_TOKEN" --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "title=$title" --form-string "message=$message" \
        https://api.pushover.net/1/messages.json >/dev/null 2>&1 || true
}

# Reject paths that are too dangerous (root, /mnt, or too shallow)
is_safe_delete_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == "/" ]] && return 1
    [[ "$p" == "/mnt" ]] && return 1
    [[ "$p" == "/mnt/"* ]] && [[ "$p" != "/mnt/"*/* ]] && return 1
    return 0
}

main() {
    if ! is_safe_delete_path "$DIR_PATH"; then
        log "Refusing to delete: path is too dangerous (use a full subdirectory, e.g. /mnt/user/downloads/...)"
        return 1
    fi
    if [[ ! -d "$DIR_PATH" ]]; then
        log "Directory not found: $DIR_PATH"
        return 1
    fi

    # Validate Pushover configuration (both or neither)
    if [[ -n "$PUSHOVER_APP_TOKEN" ]] && [[ -z "$PUSHOVER_USER_KEY" ]]; then
        log "Warning: PUSHOVER_APP_TOKEN is set but PUSHOVER_USER_KEY is missing. Notifications disabled."
        PUSHOVER_APP_TOKEN=""
    elif [[ -z "$PUSHOVER_APP_TOKEN" ]] && [[ -n "$PUSHOVER_USER_KEY" ]]; then
        log "Warning: PUSHOVER_USER_KEY is set but PUSHOVER_APP_TOKEN is missing. Notifications disabled."
        PUSHOVER_USER_KEY=""
    fi

    # Measure before deletion
    before_count=$(find "$DIR_PATH" -mindepth 1 2>/dev/null | wc -l)
    before_size=$(du -sh "$DIR_PATH" 2>/dev/null | awk '{print $1}')

    rm -rf "$DIR_PATH"/*

    # Measure after deletion (should be 0, but accounts for race conditions)
    after_count=$(find "$DIR_PATH" -mindepth 1 2>/dev/null | wc -l)
    deleted_count=$((before_count - after_count))

    summary="Deleted $deleted_count items in movies download folder, freed $before_size"
    log "$summary"
    send_pushover "Movie Downloads Cleared" "$summary"
}

main "$@"
