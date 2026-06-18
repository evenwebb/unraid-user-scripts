#!/bin/bash
#
# btrfs-scrub.sh
# Run a Btrfs scrub and optionally notify via Unraid dynamix.
#
# Description:
#   Scrubs SCRUB_DEVICE, logs output, and can notify on start, success, or failure.
#
# Usage:
#   ./btrfs-scrub.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - SCRUB_DEVICE: mount or device to scrub
#   - LOG_FILE: scrub log path
#   - ENABLE_NOTIFICATIONS: 1 = Unraid notify, 0 = log only
#   - NOTIFY_SCRIPT: dynamix notify path
#   - RESUME_EXISTING: 1 = continue an in-progress scrub
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

# Device or mount point to scrub
SCRUB_DEVICE="/mnt/downloads"

# Scrub log file (empty at runtime falls back to /boot/logs/scrub.log)
LOG_FILE="/boot/logs/scrub.log"

# 1 = send Unraid notifications on start/success/failure, 0 = log only
ENABLE_NOTIFICATIONS="1"

# Unraid Dynamix notify script (used when ENABLE_NOTIFICATIONS=1)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# 1 = resume existing scrub if one is already in progress (instead of erroring)
RESUME_EXISTING="1"

###############################################################################

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
}

# Validate LOG_FILE after log functions are defined so we can use log_err
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    log_err "LOG_FILE path invalid."
    exit 1
fi

# Validate NOTIFY_SCRIPT path for safety
if [[ "$ENABLE_NOTIFICATIONS" == "1" ]] && [[ -n "$NOTIFY_SCRIPT" ]]; then
    if [[ "$NOTIFY_SCRIPT" == *".."* || "$NOTIFY_SCRIPT" == "-"* ]]; then
        log_err "NOTIFY_SCRIPT path invalid."
        exit 1
    fi
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

    # Safety check for NOTIFY_SCRIPT path
    local notify_ok=0
    if [[ "$ENABLE_NOTIFICATIONS" == "1" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
        if [[ "$NOTIFY_SCRIPT" != *".."* && "$NOTIFY_SCRIPT" != "-"* ]]; then
            notify_ok=1
        fi
    fi

    # Check for existing scrub and optionally resume
    local scrub_action="start"
    if [[ "$RESUME_EXISTING" == "1" ]]; then
        local scrub_status
        scrub_status=$(btrfs scrub status "$SCRUB_DEVICE" 2>/dev/null)
        if echo "$scrub_status" | grep -qi "running"; then
            log "Scrub already in progress, cancelling and restarting..."
            btrfs scrub cancel "$SCRUB_DEVICE" 2>/dev/null || true
            sleep 2
        fi
    fi

    if [[ $notify_ok -eq 1 ]]; then
        if ! "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub started" -i "normal" -m "Scrubbing $SCRUB_DEVICE"; then
            log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script."
        fi
    else
        [[ "$ENABLE_NOTIFICATIONS" == "1" ]] && log "Notify script not found — running without notifications."
    fi

    if btrfs scrub start -B "$SCRUB_DEVICE" > "$log_dest" 2>&1; then
        if [[ $notify_ok -eq 1 ]]; then
            if ! "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub finished successfully" -i "normal" -m "Log: $log_dest"; then
                log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script."
            fi
        fi
        log "Scrub finished successfully. Log: $log_dest"
    else
        local scrub_exit=$?
        if [[ $notify_ok -eq 1 ]]; then
            if ! "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub failed or found errors" -i "alert" -m "Check log: $log_dest"; then
                log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script."
            fi
        fi
        log_err "Scrub failed (exit $scrub_exit). Check $log_dest for details."
        return 1
    fi
}

main "$@"
