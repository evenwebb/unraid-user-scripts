#!/bin/bash
#
# parity-check-monitor.sh
# Monitor parity check progress and notify on milestones and completion.
#
# Description:
#   Run on a schedule while a parity check is active. Exits quietly when idle.
#
# Usage:
#   ./parity-check-monitor.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - VAR_INI: Unraid parity-check state file
#   - NOTIFY_ON_START / NOTIFY_ON_PROGRESS / NOTIFY_ON_COMPLETION / NOTIFY_ON_ERRORS
#   - PROGRESS_MILESTONE_PCT: notify every N percent
#   - NOTIFY_SCRIPT: dynamix notify path
#   - LOG_FILE / STATE_FILE: optional logging and state
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

# Unraid parity-check state (Settings → Scheduler → Parity Check)
VAR_INI="/var/local/emhttp/var.ini"

# 1 = notify when a new parity check starts
NOTIFY_ON_START="1"

# 1 = notify at progress milestones (e.g. every 25%)
NOTIFY_ON_PROGRESS="1"

# Progress milestone interval in percent (must be a divisor of 100)
PROGRESS_MILESTONE_PCT="25"

# 1 = notify when parity check completes
NOTIFY_ON_COMPLETION="1"

# 1 = escalate alert if parity check found errors
NOTIFY_ON_ERRORS="1"

# Unraid Dynamix notify script (empty = disabled)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# State file for tracking check transitions
STATE_FILE=""

# Default state file: same dir as this script
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$STATE_FILE" ]] && STATE_FILE="${_SCRIPT_DIR}/parity-check.state"
unset _SCRIPT_DIR

###############################################################################

# Validate paths
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    _ui_msg="Error: LOG_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
    exit 1
fi
if [[ -n "$NOTIFY_SCRIPT" ]] && [[ "$NOTIFY_SCRIPT" == *".."* || "$NOTIFY_SCRIPT" == "-"* ]]; then
    _ui_msg="Error: NOTIFY_SCRIPT path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
    exit 1
fi
if [[ -n "$STATE_FILE" ]] && [[ "$STATE_FILE" == *".."* || "$STATE_FILE" == "-"* ]]; then
    _ui_msg="Error: STATE_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
    exit 1
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
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'''
'''* ]] && return 1
    return 0
}

send_unraid_notify() {
    local event="$1" subject="$2" description="$3" importance="${4:-normal}"
    [[ -z "$NOTIFY_SCRIPT" || ! -x "$NOTIFY_SCRIPT" ]] && return 0
    if ! is_safe_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path is not allowed. Check NOTIFY_SCRIPT in this script."
        return 1
    fi
    if ! "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "$importance"; then
        log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script (currently: $NOTIFY_SCRIPT)."
        return 1
    fi
}

# Read a key from var.ini (simple ini parser: key="value")
ini_get() {
    local file="$1" key="$2"
    grep -oP "^${key}=\K.*" "$file" 2>/dev/null | tr -d '"' || echo ""
}

# Read state file: <last_check_uuid> <last_position_pct>
read_parity_state() {
    local f="$1"
    [[ ! -f "$f" || ! -r "$f" ]] && { echo "none 0" && return 0; }
    tr -d '\r' < "$f" 2>/dev/null || echo "none 0"
}

write_parity_state() {
    local f="$1" uuid="$2" pct="$3" dir state_tmp
    dir=$(dirname "$f")
    if [[ ! -d "$dir" || ! -w "$dir" ]]; then
        log_err "Cannot write state directory: $dir"
        return 1
    fi
    state_tmp="${f}.tmp.$$"
    printf '%s %s\n' "$uuid" "$pct" > "$state_tmp" 2>/dev/null || { log_err "Cannot write state temp file"; return 1; }
    mv -f "$state_tmp" "$f" 2>/dev/null || { rm -f "$state_tmp" 2>/dev/null || true; log_err "Cannot commit state file: $f"; return 1; }
}

# Format seconds to human readable
format_duration() {
    local secs="${1:-0}"
    local d=$((secs / 86400))
    local h=$(((secs % 86400) / 3600))
    local m=$(((secs % 3600) / 60))
    if [[ $d -gt 0 ]]; then
        printf '%dd %dh %dm' $d $h $m
    elif [[ $h -gt 0 ]]; then
        printf '%dh %dm' $h $m
    else
        printf '%dm' $m
    fi
}

main() {
    if [[ ! -r "$VAR_INI" ]]; then
        log_err "Cannot read $VAR_INI — is Unraid emhttp running? Check VAR_INI in this script."
        return 1
    fi
    if [[ ! "$PROGRESS_MILESTONE_PCT" =~ ^[0-9]+$ ]] || [[ "$PROGRESS_MILESTONE_PCT" -eq 0 ]]; then
        log_err "PROGRESS_MILESTONE_PCT must be a positive integer."
        return 1
    fi

    local md_state md_resync_pos md_resync_size md_resync_errors md_resync_action
    md_state=$(ini_get "$VAR_INI" "mdState")
    md_resync_pos=$(ini_get "$VAR_INI" "mdResyncPos")
    md_resync_size=$(ini_get "$VAR_INI" "mdResyncSize")
    md_resync_errors=$(ini_get "$VAR_INI" "mdResyncDb")
    md_resync_action=$(ini_get "$VAR_INI" "mdResyncAction")

    local is_checking=0
    if [[ "$md_state" == "RECON_DLP" || "$md_state" == "PARITY" ]]; then
        is_checking=1
    fi

    if [[ $is_checking -eq 0 ]]; then
        # No check running — detect if one just finished
        local last_uuid last_pct
        read -r last_uuid last_pct < <(read_parity_state "$STATE_FILE")
        if [[ "$last_uuid" != "none" ]]; then
            log "Parity check finished (was at ${last_pct}%)."
            if [[ "$NOTIFY_ON_COMPLETION" == "1" ]]; then
                local kind="${md_resync_action:-parity check}"
                local errors_msg=""
                if [[ "${md_resync_errors:-0}" -gt 0 ]]; then
                    errors_msg="Found ${md_resync_errors} sync error(s)."
                fi
                send_unraid_notify "Parity Check Complete" "Parity check finished" \
                    "The $kind has completed.${errors_msg:+ $errors_msg}" \
                    "${errors_msg:+alert}" || send_unraid_notify "Parity Check Complete" "Parity check finished" \
                    "The $kind has completed. No errors detected." "normal"
            fi
            if [[ "$NOTIFY_ON_ERRORS" == "1" ]] && [[ "${md_resync_errors:-0}" -gt 0 ]]; then
                send_unraid_notify "Parity Check Errors" "Parity check found errors" \
                    "${md_resync_errors} sync error(s) detected during the last parity check. Review the Unraid dashboard." \
                    "alert"
            fi
            write_parity_state "$STATE_FILE" "none" 0
        fi
        log "No parity check in progress."
        return 0
    fi

    # Parity check IS running
    local current_pct=0 current_pos="${md_resync_pos:-0}" total_size="${md_resync_size:-1}"

    if [[ "$total_size" -gt 0 ]]; then
        current_pct=$((current_pos * 100 / total_size))
    fi
    local kind="${md_resync_action:-parity check}"
    local errors="${md_resync_errors:-0}"
    local check_uuid="${md_resync_pos:-0}-${md_resync_size:-0}"

    # Read last state
    local last_uuid last_pct
    read -r last_uuid last_pct < <(read_parity_state "$STATE_FILE")

    # Detect if this is a new check
    if [[ "$last_uuid" == "none" || "$last_uuid" != "$check_uuid" ]]; then
        log "New $kind detected: ${current_pct}% complete (position ${current_pos} / ${total_size})."
        if [[ "$NOTIFY_ON_START" == "1" ]]; then
            send_unraid_notify "Parity Check Start" "Parity check started" \
                "A $kind has started. Current position: ${current_pct}%. Duration varies based on array size." \
                "normal"
        fi
        write_parity_state "$STATE_FILE" "$check_uuid" "$current_pct"
        last_pct=0
        last_uuid="$check_uuid"
    fi

    # Progress milestone check
    if [[ "$NOTIFY_ON_PROGRESS" == "1" && "$current_pct" -gt "$last_pct" ]]; then
        local milestone_step="$PROGRESS_MILESTONE_PCT"
        local last_milestone=$((last_pct / milestone_step))
        local current_milestone=$((current_pct / milestone_step))

        if [[ "$current_milestone" -gt "$last_milestone" ]]; then
            # Calculate ETA based on progress so far
            local eta_secs=0
            if [[ "$current_pct" -gt 0 ]]; then
                # Read elapsed time from syslog
                local elapsed_secs
                elapsed_secs=$(grep "mdcmd.*check" /var/log/syslog 2>/dev/null | tail -1 | grep -oP 'elapsed=\K[0-9.]+' | awk '{print int($1)}' || echo 0)
                if [[ "$elapsed_secs" -gt 0 ]]; then
                    eta_secs=$((elapsed_secs * (100 - current_pct) / current_pct))
                fi
            fi
            local eta_str=""
            [[ "$eta_secs" -gt 0 ]] && eta_str=", ETA: $(format_duration $eta_secs)"

            log "Progress milestone: ${current_pct}%${eta_str}."
            send_unraid_notify "Parity Check Progress" "Parity check: ${current_pct}%" \
                "The $kind is ${current_pct}% complete${eta_str}. Errors so far: $errors." \
                "normal"
        fi
    fi

    # Write updated state
    write_parity_state "$STATE_FILE" "$check_uuid" "$current_pct"

    log "$kind in progress: ${current_pct}% (errors: $errors)"
    return 0
}

main "$@"
