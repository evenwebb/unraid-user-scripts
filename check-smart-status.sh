#!/bin/bash
#
# check-smart-status.sh
# Checks SMART health status of disks and sends an Unraid notification if any fail
#
# Description:
#   Runs smartctl -H on configured disks (or auto-detects via smartctl --scan).
#   If any disk reports SMART health FAILED, sends an alert via Unraid dynamix.
#   Schedule (e.g. daily) to get notified of disk problems early.
#
# Usage:
#   ./check-smart-status.sh
#
# Configuration (edit script variables below):
#   - DISKS: Array of disk devices (e.g. /dev/sda /dev/sdb). Empty = auto-detect.
#   - NOTIFY_SCRIPT: Unraid dynamix notify script path
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#
# Logging (Unraid-friendly):
#   - Main output goes to stdout so Unraid User Scripts captures it in the GUI.
#   - When LOG_FILE is set, each log line is also appended to that file.
#   - LOG_FILE is validated: rejects paths with "..", starting with "-", or newlines.
#
# Requires: root (smartctl needs root for most devices)
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Disks to check - leave empty to auto-detect via smartctl --scan
DISKS=()

# Unraid dynamix notify script
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Validate LOG_FILE path (reject path traversal, option-like paths, newlines)
if [[ -n "$LOG_FILE" ]]; then
    if [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* || "$LOG_FILE" == *$'\n'* ]]; then
        echo "Error: LOG_FILE path invalid (reject .., - prefix, or newlines)." >&2
        exit 1
    fi
fi

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

is_safe_path() {
    local p="$1"
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    return 0
}

main() {
    if ! command -v smartctl &>/dev/null; then
        log_err "smartctl is required. Install smartmontools."
        return 1
    fi
    if [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi

    local -a disks_to_check=()
    if [[ ${#DISKS[@]} -gt 0 ]]; then
        for d in "${DISKS[@]}"; do
            [[ -z "$d" ]] && continue
            if ! is_safe_path "$d"; then
                log_err "Skipping unsafe disk path: $d"
                continue
            fi
            disks_to_check+=("$d")
        done
    else
        while IFS= read -r dev; do
            [[ -n "$dev" ]] && disks_to_check+=("$dev")
        done < <(smartctl --scan 2>/dev/null | awk '{print $1}')
    fi

    if [[ ${#disks_to_check[@]} -eq 0 ]]; then
        log_err "No disks to check. Set DISKS in script or ensure smartctl --scan finds devices."
        return 1
    fi

    log "Checking SMART status of ${#disks_to_check[@]} disk(s)..."

    local failed_disks=()
    local checked=0

    for disk in "${disks_to_check[@]}"; do
        [[ -z "$disk" ]] && continue
        if [[ ! -b "$disk" ]]; then
            log "Skipping $disk (not a block device)"
            continue
        fi

        local output
        output=$(smartctl -H "$disk" 2>/dev/null || true)
        ((checked++)) || true

        if echo "$output" | grep -qi "SMART overall-health self-assessment test result: PASSED"; then
            log "  $disk: PASSED"
        elif echo "$output" | grep -qi "SMART overall-health self-assessment test result: FAILED"; then
            log "  $disk: FAILED"
            failed_disks+=("$disk")
        else
            log "  $disk: Unknown (no SMART data or unsupported)"
        fi
    done

    log "Checked $checked disk(s)."

    if [[ ${#failed_disks[@]} -gt 0 ]]; then
        local failed_list
        failed_list=$(IFS=,; echo "${failed_disks[*]}")
        log_err "SMART failure(s) on: $failed_list"
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" -e "SMART Check" -s "Disk health alert" \
                -d "SMART FAILED on: $failed_list" -i "alert"
        else
            log "Warning: NOTIFY_SCRIPT not executable, alert not sent."
        fi
        return 1
    fi

    log "All disks passed SMART health check."
}

main "$@"
