#!/bin/bash
#
# check-smart-status.sh
# Alert when any disk fails SMART health checks.
#
# Description:
#   Schedule daily or weekly. Sends Unraid notification if a disk reports failed SMART.
#
# Usage:
#   ./check-smart-status.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - DISKS: disk list (empty = auto-detect)
#   - NOTIFY_SCRIPT: dynamix notify path
#   - LOG_FILE: optional log file (empty = stdout only)
#
# Requires: root (run with sudo)
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

# Disks to check (e.g. /dev/sda); leave empty to auto-detect all disks
DISKS=()

# Unraid Dynamix notify script (empty = disabled)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

###############################################################################

# Validate LOG_FILE path (reject path traversal, option-like paths, newlines)
if [[ -n "$LOG_FILE" ]]; then
    if [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* || "$LOG_FILE" == *$'\n'* ]]; then
        _ui_msg="Error: LOG_FILE path invalid (reject .., - prefix, or newlines)."
        echo "$_ui_msg"
        echo "$_ui_msg" >&2
        exit 1
    fi
fi

###############################################################################

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    return 0
}

# Map smartctl --scan paths to a block device smartctl -H can use (e.g. /dev/nvme0 -> /dev/nvme0n1).
# Prints the resolved path on stdout only (no logging - safe for command substitution).
resolve_smart_disk() {
    local disk="$1"
    local ns

    if [[ -b "$disk" ]]; then
        printf '%s' "$disk"
        return 0
    fi

    if [[ "$disk" =~ ^/dev/nvme([0-9]+)$ ]]; then
        shopt -s nullglob
        for ns in /dev/nvme"${BASH_REMATCH[1]}"n*; do
            if [[ -b "$ns" ]]; then
                shopt -u nullglob
                printf '%s' "$ns"
                return 0
            fi
        done
        shopt -u nullglob
        return 1
    fi

    return 1
}

smartctl_health_args() {
    local disk="$1"
    if [[ "$disk" =~ ^/dev/nvme ]]; then
        printf '%s' "-d nvme"
    fi
}

smart_health_status() {
    local output="$1"
    if echo "$output" | grep -qiE 'SMART Health Status:[[:space:]]*OK|SMART overall-health.*PASSED|SMART.*PASSED'; then
        echo "passed"
    elif echo "$output" | grep -qiE 'SMART Health Status:[[:space:]]*FAILED|SMART overall-health.*FAILED|SMART.*FAILED'; then
        echo "failed"
    else
        echo "unknown"
    fi
}

main() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_err "Must run as root (e.g. sudo)."
        return 1
    fi
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
        log_err "No disks to check. Set DISKS in this script or ensure smartctl --scan finds devices (run as root if needed)."
        return 1
    fi

    log "Checking SMART status of ${#disks_to_check[@]} disk(s)..."

    local failed_disks=()
    local unknown_disks=()
    local checked=0
    declare -A checked_disks=()

    for disk in "${disks_to_check[@]}"; do
        [[ -z "$disk" ]] && continue
        local raw_disk="$disk" smart_disk smartctl_extra health status
        smart_disk=$(resolve_smart_disk "$disk") || {
            if [[ -e "$disk" ]]; then
                log "Skipping $disk (not a block device - use /dev/sdX or /dev/nvme0n1)"
            else
                log "Skipping $disk (device not found - check the path or add it to DISKS in this script)"
            fi
            continue
        }
        if [[ "$smart_disk" != "$raw_disk" ]]; then
            log "  $raw_disk is an NVMe controller; checking namespace $smart_disk instead"
        fi
        if [[ -n "${checked_disks[$smart_disk]:-}" ]]; then
            continue
        fi
        checked_disks[$smart_disk]=1
        disk="$smart_disk"

        local err_file output err_text
        err_file=$(mktemp) || { log_err "Could not create temp file."; continue; }
        smartctl_extra=$(smartctl_health_args "$disk")
        # shellcheck disable=SC2086
        output=$(smartctl $smartctl_extra -H "$disk" 2>"$err_file") || output=""
        err_text=$(tr '\n' ' ' <"$err_file" | sed 's/  */ /g')
        rm -f "$err_file"
        ((checked++)) || true

        if [[ -z "$output" && -n "$err_text" ]]; then
            log_err "  $disk: smartctl failed - ${err_text} (try running this script as root if permission was denied)"
            unknown_disks+=("$disk")
            continue
        fi

        status=$(smart_health_status "$output")
        case "$status" in
            passed)
                log "  $disk: PASSED"
                ;;
            failed)
                log "  $disk: FAILED"
                failed_disks+=("$disk")
                ;;
            *)
                log "  $disk: Unknown (no SMART data or unsupported device)"
                unknown_disks+=("$disk")
                ;;
        esac
    done

    log "Checked $checked disk(s)."

    if [[ ${#unknown_disks[@]} -gt 0 ]]; then
        local unknown_list
        unknown_list=$(IFS=,; echo "${unknown_disks[*]}")
        log_err "SMART status unreadable on: $unknown_list"
    fi

    if [[ ${#failed_disks[@]} -gt 0 ]]; then
        local failed_list
        failed_list=$(IFS=,; echo "${failed_disks[*]}")
        log_err "SMART failure(s) on: $failed_list"
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            if ! "$NOTIFY_SCRIPT" -e "SMART Check" -s "Disk health alert" \
                -d "SMART FAILED on: $failed_list" -i "alert"; then
                log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script (currently: $NOTIFY_SCRIPT)."
            fi
        else
            log_err "NOTIFY_SCRIPT is not executable - alert was not sent. Check NOTIFY_SCRIPT in this script."
        fi
        return 1
    fi

    if [[ ${#unknown_disks[@]} -gt 0 ]]; then
        return 1
    fi

    log "All disks passed SMART health check."
}

main "$@"
