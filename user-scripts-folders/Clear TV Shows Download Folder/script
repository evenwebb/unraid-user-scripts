#!/bin/bash
#
# clear-tv-shows-download-folder.sh
# Empty the TV shows download folder (with optional age filter).
#
# Description:
#   Deletes files under DIR_PATH. Use DRY_RUN first on production systems.
#
# Usage:
#   ./clear-tv-shows-download-folder.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only (default), 0 = delete files
#
# Configuration (edit script variables below):
#   - DIR_PATH: folder to clear
#   - MIN_AGE_MINUTES: skip files newer than N minutes (0 = all)
#   - DRY_RUN: 1 = preview only (default), 0 = delete files
#   - NOTIFY_SCRIPT: optional completion notify
#   - LOG_FILE: optional log file
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

# TV shows download directory
DIR_PATH="/mnt/user/downloads/complete/tv"

# 1 = preview only, 0 = delete contents
DRY_RUN="1"

# Skip items modified less than N minutes ago (0 = no minimum age)
MIN_AGE_MINUTES="5"

# Unraid Dynamix notify script (empty = disabled)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

###############################################################################

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    _ui_msg="Error: LOG_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
    exit 1
fi
if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    exec > >(tee -a "$LOG_FILE")
fi

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
}

is_safe_notify_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

send_unraid_notify() {
    local event="$1" subject="$2" description="$3"
    [[ -z "$NOTIFY_SCRIPT" || ! -x "$NOTIFY_SCRIPT" ]] && return 0
    if ! is_safe_notify_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path is not allowed. Check NOTIFY_SCRIPT in this script."
        return 1
    fi
    if ! "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "normal"; then
        log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script (currently: $NOTIFY_SCRIPT)."
        return 1
    fi
}

# Reject paths that are too dangerous (root, /mnt, too shallow, .. or - prefix)
is_safe_delete_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    [[ "$p" == "/" ]] && return 1
    [[ "$p" == "/mnt" ]] && return 1
    [[ "$p" == "/mnt/"* ]] && [[ "$p" != "/mnt/"*/* ]] && return 1
    return 0
}

clear_directory_contents() {
    local dir="$1"
    local age_args=()
    if [[ "$MIN_AGE_MINUTES" -gt 0 ]] && [[ "$MIN_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
        age_args=(-mmin "+${MIN_AGE_MINUTES}")
    fi
    find "$dir" -mindepth 1 -maxdepth 1 "${age_args[@]}" -exec rm -rf -- {} + 2>/dev/null
}

main() {
    if ! is_safe_delete_path "$DIR_PATH"; then
        log_err "Refusing to delete: path is too dangerous (use a full subdirectory, e.g. /mnt/user/downloads/...)"
        return 1
    fi
    if [[ ! -d "$DIR_PATH" ]]; then
        log_err "Directory not found: $DIR_PATH"
        return 1
    fi

    if [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_notify_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi
    if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
        log_err "DRY_RUN must be 0 or 1."
        return 1
    fi

    # Measure before deletion
    local age_args=()
    if [[ "$MIN_AGE_MINUTES" -gt 0 ]] && [[ "$MIN_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
        age_args=(-mmin "+${MIN_AGE_MINUTES}")
    fi
    before_count=$(find "$DIR_PATH" -mindepth 1 "${age_args[@]}" 2>/dev/null | wc -l)
    before_size=$(du -sh "$DIR_PATH" 2>/dev/null | awk '{print $1}')

    if [[ "$DRY_RUN" == "1" ]]; then
        summary="DRY-RUN: would delete $before_count items in TV shows download folder, freeing $before_size"
        log "$summary"
        send_unraid_notify "Clear TV Shows Download Folder" "TV Show Downloads Clear Preview" "$summary"
        return 0
    fi

    clear_directory_contents "$DIR_PATH" || { log_err "clear failed for $DIR_PATH"; return 1; }

    # Measure after deletion (should be 0, but accounts for race conditions)
    after_count=$(find "$DIR_PATH" -mindepth 1 2>/dev/null | wc -l)
    deleted_count=$((before_count - after_count))

    summary="Deleted $deleted_count items in TV shows download folder, freed $before_size"
    log "$summary"
    send_unraid_notify "Clear TV Shows Download Folder" "TV Show Downloads Cleared" "$summary"
}

main "$@"
