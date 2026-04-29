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

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# System log path - may be /var/log/syslog or /var/log/messages on some systems
SYSLOG_PATH="/var/log/syslog"

# Unraid dynamix notify script
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid." >&2
    exit 1
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
    oom_count=$(grep -c "Out of memory" "$SYSLOG_PATH" 2>/dev/null || echo "0")
    if [[ "$oom_count" -gt 0 ]]; then
        log "OOM error(s) found in syslog ($oom_count occurrence(s))."
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" -e "OOM Checker" -s "Checked for OOM in syslog" -d "OOM error found in syslog ($oom_count occurrence(s))" -i "alert"
        else
            log "Warning: NOTIFY_SCRIPT not executable, alert not sent."
        fi
        return 1
    fi
    log "No OOM errors found."
}

main "$@"
