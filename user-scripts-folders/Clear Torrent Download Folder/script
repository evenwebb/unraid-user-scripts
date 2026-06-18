#!/bin/bash
#
# clear-torrent-download-folder.sh
# Empty the torrent download folder (with optional age filter).
#
# Description:
#   Deletes top-level files/folders under DIR_PATH. Use DRY_RUN first on production systems.
#
# Usage:
#   ./clear-torrent-download-folder.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only (default), 0 = delete files
#
# Configuration (edit script variables below):
#   - DIR_PATH: folder to clear
#   - MIN_AGE_MINUTES: skip files newer than N minutes (0 = all)
#   - DRY_RUN / NOTIFY_SCRIPT / LOG_FILE
#
# Note: Progress and errors print to stdout; Unraid User Scripts shows that in the run window. Optional LOG_FILE also appends a copy to disk.
#
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0 · https://github.com/evenwebb/unraid-user-scripts

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Torrent download directory
DIR_PATH="/mnt/user/downloads/complete/torrents"

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
    echo "Error: LOG_FILE path invalid." >&2
    exit 1
fi
if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    exec > >(tee -a "$LOG_FILE")
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
}

is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

is_safe_delete_path() {
    local p="$1"
    is_safe_path "$p" || return 1
    [[ "$p" == "/" || "$p" == "/mnt" ]] && return 1
    [[ "$p" == "/mnt/"* ]] && [[ "$p" != "/mnt/"*/* ]] && return 1
    return 0
}

_human_bytes() {
    local b="${1:-0}"
    if [[ "$b" -ge 1073741824 ]]; then echo "$((b / 1073741824))G"
    elif [[ "$b" -ge 1048576 ]]; then echo "$((b / 1048576))M"
    elif [[ "$b" -ge 1024 ]]; then echo "$((b / 1024))K"
    else echo "${b}B"; fi
}

send_notify() {
    local subject="$1" description="$2"
    [[ -z "$NOTIFY_SCRIPT" || ! -x "$NOTIFY_SCRIPT" ]] && return 0
    if ! is_safe_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path is not allowed."
        return 1
    fi
    if ! "$NOTIFY_SCRIPT" -e "Clear Torrent Download Folder" -s "$subject" -d "$description" -i "normal"; then
        log_err "Unraid notification could not be sent."
        return 1
    fi
}

clear_directory_top_level() {
    local dir="$1" item
    local age_args=()
    if [[ "$MIN_AGE_MINUTES" -gt 0 ]] && [[ "$MIN_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
        age_args=(-mmin "+${MIN_AGE_MINUTES}")
    fi
    while IFS= read -r -d '' item; do
        rm -rf -- "$item"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 "${age_args[@]}" -print0 2>/dev/null)
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
    if [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi
    if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
        log_err "DRY_RUN must be 0 or 1."
        return 1
    fi
    if [[ ! "$MIN_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
        log_err "MIN_AGE_MINUTES must be a whole number (0 or greater)."
        return 1
    fi

    local age_args=() before_count after_count deleted_count
    local before_bytes after_bytes freed_bytes summary
    if [[ "$MIN_AGE_MINUTES" -gt 0 ]]; then
        age_args=(-mmin "+${MIN_AGE_MINUTES}")
    fi
    before_count=$(find "$DIR_PATH" -mindepth 1 -maxdepth 1 "${age_args[@]}" 2>/dev/null | wc -l | tr -d ' ')
    before_bytes=$(du -sb "$DIR_PATH" 2>/dev/null | awk '{print $1}')
    [[ -z "$before_bytes" || ! "$before_bytes" =~ ^[0-9]+$ ]] && before_bytes=0

    if [[ "$DRY_RUN" == "1" ]]; then
        summary="DRY-RUN: would delete $before_count top-level item(s) in torrent download folder, freeing about $(_human_bytes "$before_bytes")"
        log "$summary"
        send_notify "Torrent Downloads Clear Preview" "$summary"
        return 0
    fi

    clear_directory_top_level "$DIR_PATH" || { log_err "clear failed for $DIR_PATH"; return 1; }

    after_count=$(find "$DIR_PATH" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    after_bytes=$(du -sb "$DIR_PATH" 2>/dev/null | awk '{print $1}')
    [[ -z "$after_bytes" || ! "$after_bytes" =~ ^[0-9]+$ ]] && after_bytes=0
    deleted_count=$((before_count - after_count))
    freed_bytes=$((before_bytes - after_bytes))
    [[ "$freed_bytes" -lt 0 ]] && freed_bytes=0

    summary="Deleted $deleted_count top-level item(s) in torrent download folder, freed about $(_human_bytes "$freed_bytes")"
    log "$summary"
    send_notify "Torrent Downloads Cleared" "$summary"
}

main "$@" || exit 1
