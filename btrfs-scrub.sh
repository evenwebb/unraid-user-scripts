#!/bin/bash
#
# btrfs-scrub.sh
# Runs a Btrfs scrub on the cache drive and reports results via Unraid notification
#
# Description:
#   Starts a Btrfs scrub on the configured cache device, logs output to a file,
#   and sends Unraid dynamix notifications on start, success, or failure.
#
# Usage:
#   ./btrfs-scrub.sh
#
# Configuration:
#   - Edit SCRUB_DEVICE to set the path to scrub (e.g. /mnt/cache or /mnt/downloads)
#   - Edit LOG_FILE to change where scrub output is saved
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Device or mount point to scrub - EDIT FOR YOUR SETUP
SCRUB_DEVICE="/mnt/downloads"

# Where to save scrub log output
LOG_FILE="/boot/logs/scrub_cache.log"

# Unraid notify script (dynamix plugin)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

main() {
    if ! command -v btrfs >/dev/null 2>&1; then
        log "Error: btrfs command not found. Install btrfs-progs package"
        return 1
    fi
    if [[ ! -d "$SCRUB_DEVICE" && ! -b "$SCRUB_DEVICE" ]]; then
        log "Path or device not found: $SCRUB_DEVICE"
        return 1
    fi
    if ! btrfs filesystem show "$SCRUB_DEVICE" &>/dev/null; then
        log "Not a Btrfs filesystem: $SCRUB_DEVICE (set SCRUB_DEVICE to a Btrfs mount point or device)"
        return 1
    fi

    if [[ ! -x "$NOTIFY_SCRIPT" ]]; then
        log "Notify script not found. Run without notifications."
    else
        "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Scrub cache drive" -d "Scrub of cache drive started" -i "normal" -m "Scrubbing message"
    fi

    if btrfs scrub start -rdB "$SCRUB_DEVICE" > "$LOG_FILE" 2>&1; then
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Scrub cache drive" -d "Scrub of cache drive finished" -i "normal" -m "$LOG_FILE"
        fi
        log "Scrub finished successfully. Log: $LOG_FILE"
    else
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Scrub cache drive" -d "Error in scrub of cache drive!" -i "alert" -m "$LOG_FILE"
        fi
        log "Scrub reported errors. Check $LOG_FILE"
        return 1
    fi
}

main "$@"
