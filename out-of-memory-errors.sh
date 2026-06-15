#!/bin/bash
#
# out-of-memory-errors.sh
# Checks syslog for OOM (Out of Memory) events and sends an Unraid notification if found
#
# Description:
#   Greps the system log for "Out of memory" messages. If any are found,
#   sends an alert via the Unraid dynamix notification system. Schedule
#   (e.g. hourly) to get notified when the system has hit OOM.
#
# Usage:
#   ./out-of-memory-errors.sh
#
# Configuration:
#   - SYSLOG_PATH: Path to syslog (default /var/log/syslog)
#   - NOTIFY_SCRIPT: Unraid dynamix notify script path
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#
# Note: Output goes to stdout; Unraid User Scripts captures it in the GUI.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# System log path - may be /var/log/syslog or /var/log/messages on some systems
SYSLOG_PATH="/var/log/syslog"

# Unraid dynamix notify script
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# 1 = extract and show which processes were killed (from OOM lines in syslog)
SHOW_KILLED_PROCESSES="1"

# 1 = track OOM count in state file, only notify when count increases
ENABLE_STATE_TRACKING="1"

# Persistent state file for tracking OOM count across runs
STATE_FILE=""

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid." >&2
    exit 1
fi

# Default state file: same dir as this script
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$STATE_FILE" ]] && STATE_FILE="${_SCRIPT_DIR}/oom-errors.state"
unset _SCRIPT_DIR

if [[ "$ENABLE_STATE_TRACKING" == "1" ]] && [[ -n "$STATE_FILE" ]]; then
    if [[ "$STATE_FILE" == *".."* || "$STATE_FILE" == "-"* ]]; then
        echo "Error: STATE_FILE path invalid." >&2
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
    echo "$msg" >&2
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
                "$NOTIFY_SCRIPT" -e "OOM Checker" -s "Checked for OOM in syslog" -d "$desc" -i "alert" || true
            else
                log "Warning: NOTIFY_SCRIPT not executable, alert not sent."
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
