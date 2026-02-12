#!/bin/bash
#
# disk-error-alert.sh
# Checks syslog for md/storage errors and sends an Unraid notification if found
#
# Description:
#   Greps the system log for md (RAID) and storage error messages. If any are
#   found, sends an alert via Unraid dynamix notification. Schedule (e.g. hourly)
#   to get notified of disk/array problems early.
#
# Usage:
#   ./disk-error-alert.sh
#
# Configuration (edit script variables below):
#   - SYSLOG_PATH: Path to syslog (default /var/log/syslog; Unraid uses this)
#   - NOTIFY_SCRIPT: Unraid dynamix notify script path
#   - ERROR_PATTERNS: Grep -E patterns for md/storage errors (edit to add/remove)
#   - EXCLUDE_PATTERNS: Lines matching these are excluded (avoids false positives)
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#
# Logging (Unraid-friendly):
#   - Main output goes to stdout so Unraid User Scripts captures it in the GUI.
#   - When LOG_FILE is set, each log line is also appended to that file.
#   - LOG_FILE path is validated: rejects "..", leading "-", or newlines.
#
# Unraid notes: Syslog is in RAM by default (clears on reboot). Enable Settings >
# Syslog Server (e.g. Mirror to flash) for persistent logs across reboots.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# System log path - /var/log/syslog or /var/log/messages on some systems
SYSLOG_PATH="/var/log/syslog"

# Unraid dynamix notify script
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Grep -E patterns for md/storage errors (each is searched; matches are counted)
ERROR_PATTERNS=(
    "read error"
    "write error"
    "writeback error"
    "Buffer I/O error"
    "Uncorrectable sector"
    "UDMA CRC"
    "I/O error.*md[0-9]"
)

# Exclude lines matching these (avoids false positives; e.g. "no read error", "error: 0")
EXCLUDE_PATTERNS=(
    "no read error"
    "no write error"
    "read error: 0"
    "read errors: 0"
    "write error: 0"
    "write errors: 0"
)

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
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

main() {
    if ! is_safe_path "$SYSLOG_PATH"; then
        log_err "SYSLOG_PATH invalid."
        return 1
    fi
    if [[ ! -r "$SYSLOG_PATH" ]]; then
        log_err "Cannot read $SYSLOG_PATH"
        return 1
    fi
    if [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi

    local pattern_count=0
    for p in "${ERROR_PATTERNS[@]}"; do
        [[ -n "$p" ]] && ((pattern_count++)) || true
    done
    if [[ $pattern_count -eq 0 ]]; then
        log_err "ERROR_PATTERNS is empty. Add at least one pattern."
        return 1
    fi

    local total_count=0
    local -a matched_patterns=()

    for pattern in "${ERROR_PATTERNS[@]}"; do
        [[ -z "$pattern" ]] && continue
        local matches count
        matches=$(grep -E "$pattern" "$SYSLOG_PATH" 2>/dev/null || true)
        local excl_parts=()
        for p in "${EXCLUDE_PATTERNS[@]}"; do
            [[ -n "$p" ]] && excl_parts+=("$p")
        done
        if [[ ${#excl_parts[@]} -gt 0 ]]; then
            local excl
            excl=$(IFS='|'; echo "${excl_parts[*]}")
            matches=$(echo "$matches" | grep -v -E "$excl" 2>/dev/null || true)
        fi
        count=0
        if [[ -n "$matches" ]]; then
            count=$(echo "$matches" | grep -c . 2>/dev/null)
            [[ -z "$count" || "$count" != *[0-9]* ]] && count=0
        fi
        if [[ "$count" -gt 0 ]]; then
            total_count=$((total_count + count))
            matched_patterns+=("$pattern: $count")
        fi
    done

    if [[ $total_count -gt 0 ]]; then
        log "Disk/storage error(s) found in syslog ($total_count occurrence(s))."
        log "Matched: ${matched_patterns[*]}"
        if [[ -n "$NOTIFY_SCRIPT" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
            local detail message
            if [[ $total_count -eq 1 ]]; then
                detail="1 disk/storage error found in syslog. Check Tools > Diagnostics for details."
            else
                detail="$total_count disk/storage errors found in syslog. Check Tools > Diagnostics for details."
            fi
            message=$(printf '  • %s\n' "${matched_patterns[@]}")
            message="${message%$'\n'}"
            "$NOTIFY_SCRIPT" -e "Disk Error Alert" -s "Disk Storage Errors Detected" \
                -d "$detail" -m "$message" -i "alert"
        else
            log "Warning: NOTIFY_SCRIPT not executable or empty, alert not sent."
        fi
        return 1
    fi
    log "No disk/storage errors found in syslog."
    return 0
}

main "$@"
