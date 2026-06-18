#!/bin/bash
#
# out-of-memory-errors.sh
# Alert when new Out-of-Memory (OOM) events appear in syslog.
#
# Description:
#   Tracks state so repeat alerts only fire for new OOM kills.
#
# Usage:
#   ./out-of-memory-errors.sh
#   Schedule hourly.
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - SYSLOG_PATH: syslog file to scan
#   - NOTIFY_SCRIPT: dynamix notify path
#   - SHOW_KILLED_PROCESSES: 1 = include killed process names
#   - ENABLE_STATE_TRACKING: 1 = persist last-seen count
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

# System log path - may be /var/log/syslog or /var/log/messages on some systems
SYSLOG_PATH="/var/log/syslog"

# Unraid Dynamix notify script (empty = disabled)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# 1 = extract and show which processes were killed (from OOM lines in syslog)
SHOW_KILLED_PROCESSES="1"

# 1 = track OOM count in state file, only notify when count increases
ENABLE_STATE_TRACKING="1"

# OOM count state (empty = oom-errors.state beside this script)
STATE_FILE=""

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    _ui_msg="Error: LOG_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
    exit 1
fi

# Default state file: same dir as this script
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$STATE_FILE" ]] && STATE_FILE="${_SCRIPT_DIR}/oom-errors.state"
unset _SCRIPT_DIR

if [[ "$ENABLE_STATE_TRACKING" == "1" ]] && [[ -n "$STATE_FILE" ]]; then
    if [[ "$STATE_FILE" == *".."* || "$STATE_FILE" == "-"* ]]; then
        _ui_msg="Error: STATE_FILE path invalid."
        echo "$_ui_msg"
        echo "$_ui_msg" >&2
        exit 1
    fi
fi

if [[ -n "$NOTIFY_SCRIPT" ]] && [[ "$NOTIFY_SCRIPT" == *".."* || "$NOTIFY_SCRIPT" == "-"* ]]; then
    _ui_msg="Error: NOTIFY_SCRIPT path invalid."
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

read_oom_state() {
    local f="$1" line
    [[ ! -f "$f" || ! -r "$f" ]] && { echo 0; return 0; }
    IFS= read -r line < "$f" || true
    line="${line//$'\r'/}"
    line="${line//[^0-9]/}"
    [[ -z "$line" ]] && { echo 0; return 0; }
    echo "$line"
}

write_oom_state() {
    local f="$1" val="$2" dir state_tmp
    dir=$(dirname "$f")
    if [[ ! -d "$dir" || ! -w "$dir" ]]; then
        log_err "Cannot write state directory: $dir"
        return 1
    fi
    state_tmp="${f}.tmp.$$"
    printf '%s\n' "$val" > "$state_tmp" 2>/dev/null || { log_err "Cannot write state temp file"; return 1; }
    mv -f "$state_tmp" "$f" 2>/dev/null || { rm -f "$state_tmp" 2>/dev/null || true; log_err "Cannot commit state file: $f"; return 1; }
}

main() {
    if [[ -z "$SYSLOG_PATH" ]] || [[ "$SYSLOG_PATH" == *".."* || "$SYSLOG_PATH" == "-"* ]]; then
        log_err "SYSLOG_PATH invalid."
        return 1
    fi
    if [[ ! -r "$SYSLOG_PATH" ]]; then
        log_err "Cannot read $SYSLOG_PATH"
        return 1
    fi

    local oom_count
    oom_count=$(grep -c "Out of memory" "$SYSLOG_PATH" 2>/dev/null || true)
    oom_count="${oom_count:-0}"

    local last_count=0
    if [[ "$ENABLE_STATE_TRACKING" == "1" ]]; then
        last_count=$(read_oom_state "$STATE_FILE")
    fi

    if [[ "$oom_count" -gt 0 ]]; then
        log "OOM error(s) found in syslog ($oom_count occurrence(s); last recorded: $last_count)."

        local process_info=""
        if [[ "$SHOW_KILLED_PROCESSES" == "1" ]]; then
            local killed
            killed=$(grep -E "(Killed process|oom_reaper.*victim)" "$SYSLOG_PATH" 2>/dev/null | grep -oP '(?:Killed process \d+ \(|victim:)\K[^)\s]+' | sort -u | paste -sd ', ' - 2>/dev/null || echo "")
            if [[ -n "$killed" ]]; then
                process_info="  Killed process(es): $killed"
            fi
        fi

        local should_notify=1
        if [[ "$ENABLE_STATE_TRACKING" == "1" ]]; then
            if [[ "$oom_count" -le "$last_count" ]]; then
                should_notify=0
                log "OOM count unchanged or decreased; no notification sent."
            fi
        fi

        if [[ "$should_notify" -eq 1 ]]; then
            if [[ -x "$NOTIFY_SCRIPT" ]]; then
                local desc="OOM error found in syslog ($oom_count occurrence(s))."
                [[ -n "$process_info" ]] && desc+=$'\n'"$process_info"
                if ! "$NOTIFY_SCRIPT" -e "OOM Checker" -s "Checked for OOM in syslog" -d "$desc" -i "alert"; then
                    log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script (currently: $NOTIFY_SCRIPT)."
                fi
            else
                log_err "NOTIFY_SCRIPT is not executable — alert was not sent. Check NOTIFY_SCRIPT in this script."
            fi
            if [[ "$ENABLE_STATE_TRACKING" == "1" ]]; then
                write_oom_state "$STATE_FILE" "$oom_count" || true
            fi
        fi
        return 1
    fi

    if [[ "$ENABLE_STATE_TRACKING" == "1" && "$last_count" -ne 0 ]]; then
        write_oom_state "$STATE_FILE" 0 || true
    fi
    log "No OOM errors found."
    return 0
}

main "$@"
