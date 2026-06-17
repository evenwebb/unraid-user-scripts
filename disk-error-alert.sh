#!/bin/bash
#
# disk-error-alert.sh
# Alert on new md/storage errors in syslog.
#
# Description:
#   Counts unique error lines and notifies only when the count increases.
#
# Usage:
#   ./disk-error-alert.sh
#   Schedule hourly or daily.
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - SYSLOG_PATH: syslog file to scan
#   - NOTIFY_SCRIPT: dynamix notify path
#   - ERROR_PATTERNS / EXCLUDE_PATTERNS: match filters
#   - ENABLE_PER_DISK_TRACKING: 1 = track per-disk IDs
#   - ENABLE_SMART_CORRELATION: 1 = cross-check SMART status
#   - SMARTCTL_PATH: smartctl binary path
#   - LOG_FILE / STATE_FILE: optional logging and state
#
# Note: Output goes to stdout; Unraid User Scripts shows it in the run window.
#
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0 · https://github.com/evenwebb/unraid-user-scripts

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# System log path - /var/log/syslog or /var/log/messages on some systems
SYSLOG_PATH="/var/log/syslog"

# Unraid dynamix notify script
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Grep -E patterns for md/storage errors (each is searched; union is de-duped)
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

# 1 = extract disk identifiers (mdX, sdX) from error lines and track per-disk counts
ENABLE_PER_DISK_TRACKING="1"

# 1 = cross-reference disks with errors against SMART data (requires smartctl)
ENABLE_SMART_CORRELATION="1"

# Path to smartctl (usually /usr/sbin/smartctl on Unraid)
SMARTCTL_PATH="/usr/sbin/smartctl"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Last-seen unique matching line count. Empty = disk-error-alert.state beside
# this script. Only notifies when current total is greater than stored.
STATE_FILE=""

# Directory of this script (for default STATE_FILE)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$STATE_FILE" ]] && STATE_FILE="${_SCRIPT_DIR}/disk-error-alert.state"
unset _SCRIPT_DIR

# Validate LOG_FILE path (reject path traversal, option-like paths, newlines)
if [[ -n "$LOG_FILE" ]]; then
    if [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* || "$LOG_FILE" == *$'\n'* ]]; then
        echo "Error: LOG_FILE path invalid (reject .., - prefix, or newlines)." >&2
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

is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

# Read last saved total error count (non-negative integer only).
read_stored_error_total() {
    local f="$1" line
    [[ ! -f "$f" || ! -r "$f" ]] && { echo 0; return 0; }
    IFS= read -r line < "$f" || true
    line="${line//$'\r'/}"
    line="${line//[^0-9]/}"
    [[ -z "$line" ]] && { echo 0; return 0; }
    echo "$line"
}

write_stored_error_total() {
    # Use state_tmp (not tmp) so this never shadows main()'s temp path local.
    local f="$1" val="$2" dir state_tmp
    dir=$(dirname "$f")
    if [[ ! -d "$dir" || ! -w "$dir" ]]; then
        log_err "Cannot write state directory: $dir"
        return 1
    fi
    state_tmp="${f}.tmp.$$"
    if ! printf '%s\n' "$val" > "$state_tmp" 2>/dev/null; then
        log_err "Cannot write state temp file: $state_tmp"
        return 1
    fi
    if ! mv -f "$state_tmp" "$f" 2>/dev/null; then
        rm -f "$state_tmp" 2>/dev/null || true
        log_err "Cannot commit state file: $f"
        return 1
    fi
    return 0
}

# Extract disk identifiers (sdX, mdX, nvmeXnY) from error lines.
# Reads sorted match file ($1), prints unique disk IDs one per line.
extract_disk_ids() {
    local sorted_file="$1"
    grep -o -E '\b(sd[a-z]+|md[0-9]+|nvme[0-9]+n[0-9]+)\b' "$sorted_file" 2>/dev/null | sort -u || true
}

# Check SMART health for a disk device. Prints a one-line summary.
# $1 = device name (e.g. sda, nvme0n1)
get_smart_health() {
    local dev="$1"
    local smartctl="${SMARTCTL_PATH:-/usr/sbin/smartctl}"
    if [[ ! -x "$smartctl" ]]; then
        echo "  (smartctl not found)"
        return 0
    fi
    local dev_path="/dev/$dev"
    if [[ ! -e "$dev_path" ]]; then
        echo "  (device $dev_path not found)"
        return 0
    fi

    local health raw realloc pending udma
    # Overall health status
    health=$("$smartctl" -H "$dev_path" 2>/dev/null | grep -i 'SMART.*Health\|SMART.*PASSED\|SMART.*OK' | head -n1 | sed 's/^[[:space:]]*//' || echo "")
    [[ -z "$health" ]] && health="SMART status unknown"

    # Key attributes: Reallocated_Sector_Ct (5), Current_Pending_Sector (197), UDMA_CRC_Error_Count (199)
    raw=$("$smartctl" -A "$dev_path" 2>/dev/null)
    realloc=$(echo "$raw" | grep -E '^\s*(5|005)\s' | awk '{print $NF}' || echo "N/A")
    pending=$(echo "$raw" | grep -E '^\s*(197)\s' | awk '{print $NF}' || echo "N/A")
    udma=$(echo "$raw" | grep -E '^\s*(199)\s' | awk '{print $NF}' || echo "N/A")

    echo "  $health | Reallocated: $realloc | Pending: $pending | UDMA CRC: $udma"
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
    if ! is_safe_path "$STATE_FILE"; then
        log_err "STATE_FILE path invalid."
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

    local excl_parts=()
    for p in "${EXCLUDE_PATTERNS[@]}"; do
        [[ -n "$p" ]] && excl_parts+=("$p")
    done
    local excl=""
    if [[ ${#excl_parts[@]} -gt 0 ]]; then
        excl=$(IFS='|'; echo "${excl_parts[*]}")
    fi

    # Keep tmp/sorted always set (set -u) and avoid "$tmp" in RETURN (nounset-safe).
    local tmp="" sorted="" total_count=0
    tmp=$(mktemp /tmp/disk-error-alert.XXXXXX) || {
        log_err "mktemp failed; cannot build match list."
        return 1
    }
    if [[ -z "$tmp" ]]; then
        log_err "mktemp returned an empty path."
        return 1
    fi
    sorted="${tmp}.sorted"
    trap 'rm -f "${tmp-}" "${sorted-}" 2>/dev/null' RETURN
    : >"$tmp"

    for pattern in "${ERROR_PATTERNS[@]}"; do
        [[ -z "$pattern" ]] && continue
        if [[ -n "$excl" ]]; then
            grep -a -E "$pattern" "$SYSLOG_PATH" 2>/dev/null | grep -a -v -E "$excl" >>"$tmp" || true
        else
            grep -a -E "$pattern" "$SYSLOG_PATH" 2>/dev/null >>"$tmp" || true
        fi
    done

    LC_ALL=C sort -u "$tmp" -o "$sorted" 2>/dev/null || true
    if [[ -s "$sorted" ]]; then
        total_count=$(wc -l <"$sorted" | tr -d '[:space:]')
        # Guard against non-numeric wc output (e.g. if sorted file is missing or wc fails,
        # the result could contain error text instead of digits). Fall back to 0 in that case.
        [[ "$total_count" != *[0-9]* ]] && total_count=0
    fi

    local last_count
    last_count=$(read_stored_error_total "$STATE_FILE")

    if [[ $total_count -lt $last_count ]]; then
        log "Error count decreased ($last_count -> $total_count); treating as log rotation or cleared syslog. Updating baseline, no notification."
        write_stored_error_total "$STATE_FILE" "$total_count" || true
        last_count=$total_count
    fi

    if [[ $total_count -gt 0 ]]; then
        log "Disk/storage error(s) in syslog ($total_count unique line(s); last recorded: $last_count)."
        if [[ $total_count -le 5 ]]; then
            log "Matching lines:"$'\n'"$(sed 's/^/  /' "$sorted")"
        else
            log "First 3 matching lines:"$'\n'"$(head -n 3 "$sorted" | sed 's/^/  /')"
        fi
        if [[ $total_count -gt $last_count ]]; then
            if [[ -n "$NOTIFY_SCRIPT" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
                local detail message lines_max notify_ec
                lines_max=30
                if [[ $total_count -eq 1 ]]; then
                    detail="1 unique disk/storage error line in syslog (count increased). Check Tools > Diagnostics for details."
                else
                    detail="$total_count unique disk/storage error lines in syslog (count increased). Check Tools > Diagnostics for details."
                fi
                if [[ $total_count -le $lines_max ]]; then
                    message=$(sed 's/^/  • /' "$sorted")
                else
                    message=$(head -n "$lines_max" "$sorted" | sed 's/^/  • /')
                    message+=$'\n'"  … and $((total_count - lines_max)) more line(s)."
                fi
                message="${message%$'\n'}"
                notify_ec=0

                # Per-disk breakdown
                local disk_breakdown=""
                if [[ "$ENABLE_PER_DISK_TRACKING" == "1" ]]; then
                    local disk_ids
                    disk_ids=$(extract_disk_ids "$sorted")
                    if [[ -n "$disk_ids" ]]; then
                        disk_breakdown=$'\n'"Disks with errors:"
                        local dname dcount
                        while IFS= read -r dname; do
                            [[ -z "$dname" ]] && continue
                            dcount=$(grep -c "$dname" "$sorted" 2>/dev/null || echo 0)
                            disk_breakdown+=$'\n'"  $dname: $dcount error(s)"
                            if [[ "$ENABLE_SMART_CORRELATION" == "1" ]]; then
                                local smart_summary
                                smart_summary=$(get_smart_health "$dname")
                                disk_breakdown+=$'\n'"$smart_summary"
                            fi
                        done <<< "$disk_ids"
                        detail+="$disk_breakdown"
                    fi
                fi
                "$NOTIFY_SCRIPT" -e "Disk Error Alert" -s "Disk Storage Errors Detected" \
                    -d "$detail" -m "$message" -i "alert" || notify_ec=$?
                if [[ $notify_ec -eq 0 ]]; then
                    write_stored_error_total "$STATE_FILE" "$total_count" || true
                else
                    log_err "notify exited with status $notify_ec; state not updated (will retry if count stays above baseline)."
                fi
            else
                log "Warning: NOTIFY_SCRIPT not executable or empty, alert not sent."
            fi
        else
            log "Error count unchanged or not above baseline; no notification sent."
        fi
        return 1
    fi

    if [[ $last_count -ne 0 ]]; then
        write_stored_error_total "$STATE_FILE" 0 || true
    fi
    log "No disk/storage errors found in syslog."
    return 0
}

main "$@"
