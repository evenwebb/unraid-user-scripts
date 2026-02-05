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
#   - Set NOTIFY_SCRIPT to your Unraid notify script path if different
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# System log path - may be /var/log/syslog or /var/log/messages on some systems
SYSLOG_PATH="/var/log/syslog"

# Unraid dynamix notify script
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

main() {
    if [[ ! -r "$SYSLOG_PATH" ]]; then
        log "Cannot read $SYSLOG_PATH"
        return 1
    fi

    if grep -q "Out of memory" "$SYSLOG_PATH" 2>/dev/null; then
        log "OOM error found in syslog."
        if [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" -e "OOM Checker" -s "Checked for OOM in syslog" -d "OOM error found in syslog" -i "alert"
        fi
        return 1
    fi
    log "No OOM errors found."
}

main "$@"
