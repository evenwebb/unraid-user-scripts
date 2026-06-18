#!/bin/bash
#
# btrfs-scrub.sh
# Run a Btrfs scrub and optionally notify via Unraid dynamix.
#
# Description:
#   Scrubs one or more Btrfs filesystems, logs output, and can notify on start, success, or failure.
#
# Usage:
#   ./btrfs-scrub.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - SCRUB_DEVICES: mount points or devices to scrub
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

# Btrfs mount points or block devices to scrub (processed in order)
SCRUB_DEVICES=(
    "/mnt/downloads"
)

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

require_root() {
    if [[ "$(id -u 2>/dev/null)" != "0" ]]; then
        log_err "This script must run as root (use User Scripts schedule as root or sudo)."
        return 1
    fi
    return 0
}

# Support merged configs that still use SCRUB_DEVICE (single string).
normalize_scrub_devices() {
    local decl raw
    if declare -p SCRUB_DEVICES &>/dev/null; then
        decl=$(declare -p SCRUB_DEVICES 2>/dev/null || true)
        if [[ "$decl" != declare\ -a* ]]; then
            raw="$SCRUB_DEVICES"
            SCRUB_DEVICES=()
            SCRUB_DEVICES+=("$raw")
        fi
        return
    fi
    if declare -p SCRUB_DEVICE &>/dev/null; then
        decl=$(declare -p SCRUB_DEVICE 2>/dev/null || true)
        if [[ "$decl" == declare\ -a* ]]; then
            SCRUB_DEVICES=("${SCRUB_DEVICE[@]}")
        else
            SCRUB_DEVICES=("$SCRUB_DEVICE")
        fi
    else
        SCRUB_DEVICES=()
    fi
}
normalize_scrub_devices

validate_scrub_device() {
    local device="$1"
    device="${device%/}"
    [[ -z "$device" ]] && return 1
    [[ "$device" == *".."* || "$device" == "-"* ]] && return 1
    return 0
}

if [[ ${#SCRUB_DEVICES[@]} -eq 0 ]]; then
    log_err "SCRUB_DEVICES is empty. Add at least one mount point or device."
    exit 1
fi
for _scrub_dev in "${SCRUB_DEVICES[@]}"; do
    if ! validate_scrub_device "$_scrub_dev"; then
        log_err "Invalid path in SCRUB_DEVICES: $_scrub_dev"
        exit 1
    fi
done
unset _scrub_dev

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

notify_ok=0
if [[ "$ENABLE_NOTIFICATIONS" == "1" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
    if [[ "$NOTIFY_SCRIPT" != *".."* && "$NOTIFY_SCRIPT" != "-"* ]]; then
        notify_ok=1
    fi
fi

scrub_one_device() {
    local SCRUB_DEVICE="$1"
    local log_dest="$2"

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

    if [[ "$RESUME_EXISTING" == "1" ]]; then
        local scrub_status
        scrub_status=$(btrfs scrub status "$SCRUB_DEVICE" 2>/dev/null)
        if echo "$scrub_status" | grep -qi "running"; then
            log "Scrub already in progress on $SCRUB_DEVICE - skipping (RESUME_EXISTING=1)."
            return 0
        fi
    fi

    if [[ $notify_ok -eq 1 ]]; then
        if ! "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub started" -i "normal" -m "Scrubbing $SCRUB_DEVICE"; then
            log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script."
        fi
    fi

    log "Starting scrub on $SCRUB_DEVICE (log: $log_dest)"
    if btrfs scrub start -B "$SCRUB_DEVICE" >> "$log_dest" 2>&1; then
        if [[ $notify_ok -eq 1 ]]; then
            if ! "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub finished successfully" -i "normal" -m "Log: $log_dest"; then
                log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script."
            fi
        fi
        log "Scrub finished successfully on $SCRUB_DEVICE."
        return 0
    fi

    local scrub_exit=$?
    if [[ $notify_ok -eq 1 ]]; then
        if ! "$NOTIFY_SCRIPT" -e "start_scrub_cache" -s "Btrfs scrub: $scrub_label" -d "Scrub failed or found errors" -i "alert" -m "Check log: $log_dest"; then
            log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script."
        fi
    fi
    log_err "Scrub failed on $SCRUB_DEVICE (exit $scrub_exit). Check $log_dest for details."
    return 1
}

main() {
    require_root || return 1

    if ! command -v btrfs &>/dev/null; then
        log_err "btrfs command not found. Install btrfs-progs."
        return 1
    fi

    if [[ "$ENABLE_NOTIFICATIONS" == "1" && $notify_ok -eq 0 ]]; then
        log "Notify script not found - running without notifications."
    fi

    local log_dest="${LOG_FILE:-/boot/logs/scrub.log}"
    local log_dir
    log_dir=$(dirname "$log_dest")
    if [[ -n "$log_dir" && "$log_dir" != "." && ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || { log_err "Cannot create log directory: $log_dir"; return 1; }
    fi

    local -a devices=() device seen
    for device in "${SCRUB_DEVICES[@]}"; do
        [[ -z "$device" ]] && continue
        device="${device%/}"
        seen=0
        for d in "${devices[@]}"; do
            [[ "$d" == "$device" ]] && { seen=1; break; }
        done
        [[ $seen -eq 1 ]] && continue
        devices+=("$device")
    done

    if [[ ${#devices[@]} -eq 0 ]]; then
        log_err "No valid devices in SCRUB_DEVICES."
        return 1
    fi

    log "Scrubbing ${#devices[@]} Btrfs filesystem(s): ${devices[*]}"

    local any_failed=0 first=1
    for device in "${devices[@]}"; do
        if [[ $first -eq 1 ]]; then
            : > "$log_dest"
            first=0
        else
            {
                echo ""
                echo "========== Scrub: $device ($(date '+%Y-%m-%d %H:%M:%S')) =========="
                echo ""
            } >> "$log_dest"
        fi
        if ! scrub_one_device "$device" "$log_dest"; then
            any_failed=1
        fi
    done

    if [[ $any_failed -eq 1 ]]; then
        log_err "One or more scrubs failed. Log: $log_dest"
        return 1
    fi

    log "All scrubs finished successfully. Log: $log_dest"
}

main "$@"
