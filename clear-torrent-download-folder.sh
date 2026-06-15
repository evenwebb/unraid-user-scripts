#!/bin/bash
#
# clear-torrent-download-folder.sh
# Empties the torrent download directory and optionally sends a notification
#
# Description:
#   Counts and measures the torrent download folder, deletes all contents,
#   then prints a summary. Optionally sends an Unraid notification.
#
# Usage:
#   ./clear-torrent-download-folder.sh
#
# Configuration:
#   - DIR_PATH: Path to the torrent download folder to clear
#   - DRY_RUN: 1 = preview only, 0 = delete contents
#   - NOTIFY_SCRIPT: Optional path to dynamix notify (empty = skip notification)
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#
# Note: Output goes to stdout; Unraid User Scripts captures it in the GUI.
##   - MIN_AGE_MINUTES: Skip files modified less than N minutes ago (0 = no minimum)

# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################
 
# Torrent download directory
DIR_PATH="/mnt/user/downloads/torrents"

# 1 = preview only, 0 = delete contents
DRY_RUN="0"

# Skip items modified less than N minutes ago (0 = no minimum age)
MIN_AGE_MINUTES="5"

# Optional: Unraid dynamix notify (empty = skip notification after clear)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

###############################################################################

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid." >&2
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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
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
    is_safe_notify_path "$NOTIFY_SCRIPT" || return 0
    "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "normal" 2>/dev/null || true
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
        summary="DRY-RUN: would delete $before_count items in torrent download folder, freeing $before_size"
        log "$summary"
        send_unraid_notify "Clear Torrent Download Folder" "Torrent Downloads Clear Preview" "$summary"
        return 0
    fi

    clear_directory_contents "$DIR_PATH" || { log_err "clear failed for $DIR_PATH"; return 1; }

    # Measure after deletion (should be 0, but accounts for race conditions)
    after_count=$(find "$DIR_PATH" -mindepth 1 2>/dev/null | wc -l)
    deleted_count=$((before_count - after_count))

    summary="Deleted $deleted_count items in torrent download folder, freed $before_size"
    log "$summary"
    send_unraid_notify "Clear Torrent Download Folder" "Torrent Downloads Cleared" "$summary"
}

main "$@"
