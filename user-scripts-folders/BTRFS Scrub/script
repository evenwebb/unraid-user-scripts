#!/bin/bash
#
# btrfs-scrub.sh
# Runs a Btrfs scrub on a cache/device and reports results via Unraid notification
#
# Description:
#   Starts a Btrfs scrub on the configured device or mount point, logs output,
#   and sends Unraid dynamix notifications on start, success, or failure.
#   Uses -B to run in foreground and wait for completion.
#
# Usage:
#   ./btrfs-scrub.sh
#
# Configuration:
#   - SCRUB_DEVICE: Path or device to scrub (e.g. /mnt/cache, /mnt/downloads)
#   - LOG_FILE: Where to save scrub output; parent dir created if missing (default: /boot/logs/scrub.log)
#   - NOTIFY_SCRIPT: Unraid dynamix notify script path
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Device or mount point to scrub
SCRUB_DEVICE="/mnt/downloads"

# Where to save scrub log output (default: /boot/logs/scrub.log if empty)
LOG_FILE="/boot/logs/scrub.log"

# Unraid notify script (dynamix plugin)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

###############################################################################

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" >&2
}

# Validate LOG_FILE after log functions are defined so we can use log_err
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    log_err "LOG_FILE path invalid."
    exit 1
fi

main() {
    if ! command -v btrfs &>/dev/null; then
        log_err "btrfs command not found. Install btrfs-progs."
        return 1
    fi

    SCRUB_DEVICE="${SCRUB_DEVICE%/}"
    if [[ ! -d "$SCRUB_DEVICE" && ! -b "$SCRUB_DEVICE" ]]; then
        log_err "Path or device not found: $SCRUB_DEVICE"
        return 1
    fi
    if ! btrfs filesystem show "$SCRUB_DEVICE" &>/dev/null; then
        log_err "Not a Btrfs filesystem: $SCRUB_DEVICE"
        return 1
    fi

    local scrub_label
    scrub_label=$(basename "$SCRUB_DEVICE" 2>/dev/null || echo "$SCRUB_DEVICE")
    scrub_label="${scrub_label:-scrub}"

    local log_dest="${LOG_FILE:-/boot/logs/scrub.log}"
    local log_dir
    log_dir=$(dirname "$log_dest")
    if [[ -n "$log_dir" && "$log_dir" != "." && ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || { log_err "Cannot create log directory: $log_dir"; return 1; }
    fi

    if [[ -x "$NOTIFY_SCRIPT" ]]; then
        "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub started" -i "normal" -m "Scrubbing $SCRUB_DEVICE"
    else
        log "Notify script not found, running without notifications"
    fi

    if btrfs scrub start -B "$SCRUB_DEVICE" > "$log_dest" 2>&1; then
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub finished successfully" -i "normal" -m "Log: $log_dest"
        fi
        log "Scrub finished successfully. Log: $log_dest"
    else
        local scrub_exit=$?
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub failed or found errors" -i "alert" -m "Check log: $log_dest"
        fi
        log_err "Scrub failed (exit $scrub_exit). Check $log_dest"
        return 1
    fi
}

main "$@"
