#!/bin/bash
#
# parity-check-monitor.sh
# Version: 1.0.1
# Monitor parity-check state and notify on progress, completion, and interruption.
#
# Description:
#   Run on a schedule while a parity check is active. Tracks running and paused
#   states, progress milestones, completion, and interrupted checks.
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

# Prevent overlapping scheduled invocations
LOCK_FILE=""

# Default state file: same dir as this script
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$STATE_FILE" ]] && STATE_FILE="${_SCRIPT_DIR}/parity-check.state"
[[ -z "$LOCK_FILE" ]] && LOCK_FILE="${STATE_FILE}.lock"
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
if [[ -n "$LOCK_FILE" ]] && [[ "$LOCK_FILE" == *".."* || "$LOCK_FILE" == "-"* ]]; then
    _ui_msg="Error: LOCK_FILE path invalid."
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
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

send_unraid_notify() {
    local event="$1" subject="$2" description="$3" importance="${4:-normal}"
    [[ -z "$NOTIFY_SCRIPT" ]] && return 0
    if [[ ! -x "$NOTIFY_SCRIPT" ]]; then
        log_err "NOTIFY_SCRIPT is configured but not executable: $NOTIFY_SCRIPT"
        return 1
    fi
    if ! is_safe_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path is not allowed. Check NOTIFY_SCRIPT in this script."
        return 1
    fi
    if ! "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "$importance"; then
        log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script (currently: $NOTIFY_SCRIPT)."
        return 1
    fi
}

# Read a key from one var.ini snapshot so fields cannot come from different updates.
ini_get() {
    local snapshot="$1" key="$2"
    local line val=""
    while IFS= read -r line; do
        [[ "${line%%=*}" == "$key" ]] || continue
        val="${line#*=}"
    done <<< "$snapshot"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    val="${val#\"}"
    val="${val%\"}"
    printf '%s' "$val"
}
# Count parity/sync-related error lines in syslog since a line offset (best-effort).
get_syslog_identity() {
    local identity
    identity=$(stat -c '%d:%i:%s' /var/log/syslog 2>/dev/null) || identity=unknown
    printf '%s' "$identity"
}

count_parity_sync_errors_from_syslog() {
    local start_line="${1:-1}" expected_identity="${2:-unknown}"
    local syslog="/var/log/syslog" n current_identity
    [[ ! -r "$syslog" ]] && { echo unavailable; return 0; }
    [[ ! "$start_line" =~ ^[0-9]+$ ]] || [[ "$start_line" -lt 1 ]] && start_line=1
    current_identity=$(get_syslog_identity)
    if [[ "$expected_identity" == unknown || "$current_identity" == unknown ]]; then
        echo unavailable
        return 0
    fi
    local expected_device_inode="${expected_identity%:*}"
    local current_device_inode="${current_identity%:*}"
    local expected_size="${expected_identity##*:}"
    local current_size="${current_identity##*:}"
    if [[ "$expected_device_inode" != "${current_device_inode%:*}" || "$current_size" -lt "$expected_size" ]]; then
        echo unavailable
        return 0
    fi
    n=$(tail -n +"$start_line" "$syslog" 2>/dev/null \
        | grep -ciE 'parity.*(error|mismatch)|sync error|read error.*parity|parity.*read error' 2>/dev/null) || n=0
    [[ -z "$n" || ! "$n" =~ ^[0-9]+$ ]] && n=0
    echo "$n"
}

get_syslog_line_count() {
    local syslog="/var/log/syslog" count
    [[ ! -r "$syslog" ]] && { echo 1; return 0; }
    count=$(wc -l < "$syslog" 2>/dev/null) || count=0
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    echo $((count + 1))
}
# State fields: uuid pct syslog_start start_epoch paused_since paused_total syslog_identity.
# Older state files remain readable; old two-field files lack error-tracking data.
read_parity_state() {
    local f="$1"
    [[ ! -f "$f" || ! -r "$f" ]] && { echo "none 0 1 0 0 0 unknown 0"; return 0; }
    local line
    line=$(tr -d '\r' < "$f" 2>/dev/null | head -1)
    [[ -z "$line" ]] && { echo "none 0 1 0 0 0 unknown 0"; return 0; }
    local uuid pct start_line start_epoch paused_since paused_total syslog_identity legacy=0
    if [[ "$line" =~ ^[^[:space:]]+[[:space:]]+[0-9]+$ ]]; then
        legacy=1
    fi
    read -r uuid pct start_line start_epoch paused_since paused_total syslog_identity <<< "$line"
    uuid="${uuid:-none}"
    [[ "${pct:-}" =~ ^[0-9]+$ ]] || pct=0
    [[ "${start_line:-}" =~ ^[0-9]+$ ]] || start_line=1
    [[ "${start_epoch:-}" =~ ^[0-9]+$ ]] || start_epoch=0
    [[ "${paused_since:-}" =~ ^[0-9]+$ ]] || paused_since=0
    [[ "${paused_total:-}" =~ ^[0-9]+$ ]] || paused_total=0
    syslog_identity="${syslog_identity:-unknown}"
    echo "$uuid $pct $start_line $start_epoch $paused_since $paused_total $syslog_identity $legacy"
}

write_parity_state() {
    local f="$1" uuid="$2" pct="$3" start_line="${4:-1}" start_epoch="${5:-0}" paused_since="${6:-0}" paused_total="${7:-0}" syslog_identity="${8:-unknown}" dir state_tmp
    dir=$(dirname "$f")
    if [[ ! -d "$dir" || ! -w "$dir" ]]; then
        log_err "Cannot write state directory: $dir"
        return 1
    fi
    state_tmp="${f}.tmp.$$"
    printf '%s %s %s %s %s %s %s\n' "$uuid" "$pct" "$start_line" "$start_epoch" "$paused_since" "$paused_total" "$syslog_identity" > "$state_tmp" 2>/dev/null || { log_err "Cannot write state temp file"; return 1; }
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
    if command -v flock >/dev/null 2>&1; then
        local lock_dir
        lock_dir=$(dirname "$LOCK_FILE")
        if [[ ! -d "$lock_dir" || ! -w "$lock_dir" ]]; then
            log_err "Cannot open lock directory: $lock_dir"
            return 1
        fi
        exec 200>"$LOCK_FILE" || { log_err "Cannot open lock file: $LOCK_FILE"; return 1; }
        if ! flock -n 200; then
            log "Another parity monitor run is active; skipping this invocation."
            return 0
        fi
    else
        log "flock is unavailable; continuing without overlap protection."
    fi
    if [[ ! -r "$VAR_INI" ]]; then
        log_err "Cannot read $VAR_INI - is Unraid emhttp running? Check VAR_INI in this script."
        return 1
    fi
    if [[ ! "$PROGRESS_MILESTONE_PCT" =~ ^[0-9]+$ ]] || [[ "$PROGRESS_MILESTONE_PCT" -eq 0 ]]; then
        log_err "PROGRESS_MILESTONE_PCT must be a positive integer."
        return 1
    fi
    if [[ $((100 % PROGRESS_MILESTONE_PCT)) -ne 0 ]]; then
        log_err "PROGRESS_MILESTONE_PCT must divide 100 evenly (got: $PROGRESS_MILESTONE_PCT)."
        return 1
    fi

    local snapshot
    snapshot=$(< "$VAR_INI") || {
        log_err "Cannot read a consistent snapshot from $VAR_INI."
        return 1
    }

    local md_resync md_resync_pos md_resync_size md_resync_action
    md_resync=$(ini_get "$snapshot" "mdResync")
    md_resync_pos=$(ini_get "$snapshot" "mdResyncPos")
    md_resync_size=$(ini_get "$snapshot" "mdResyncSize")
    md_resync_action=$(ini_get "$snapshot" "mdResyncAction")

    [[ -n "$md_resync_pos" ]] || md_resync_pos=0
    [[ -n "$md_resync_size" ]] || md_resync_size=0
    if [[ ! "$md_resync_pos" =~ ^[0-9]+$ || ! "$md_resync_size" =~ ^[0-9]+$ ]]; then
        log_err "Invalid mdResyncPos or mdResyncSize in $VAR_INI."
        return 1
    fi
    if [[ -n "$md_resync" && ! "$md_resync" =~ ^[0-9]+$ ]]; then
        log_err "Invalid mdResync value in $VAR_INI."
        return 1
    fi

    local action_id="${md_resync_action//[[:space:]]/_}"
    local check_uuid="parity-check-$md_resync_size-$action_id"
    local last_uuid last_pct last_start_line last_start_epoch last_paused_since last_paused_total last_syslog_identity last_legacy
    read -r last_uuid last_pct last_start_line last_start_epoch last_paused_since last_paused_total last_syslog_identity last_legacy \
        < <(read_parity_state "$STATE_FILE")
    local is_checking=0 is_paused=0
    if [[ "$md_resync_action" =~ ^[Cc][Hh][Ee][Cc][Kk]([[:space:]]|$) ]] && [[ "$md_resync_size" -gt 0 ]]; then
        if [[ -n "$md_resync" ]]; then
            if [[ "$md_resync" -gt 0 ]]; then
                is_checking=1
            elif [[ "$md_resync_pos" -lt "$md_resync_size" &&
                    ( "$md_resync_pos" -gt 0 || "$last_uuid" == "$check_uuid" ) ]]; then
                is_checking=1
                is_paused=1
            elif [[ "$last_uuid" == "$check_uuid" && "$last_pct" -ge 100 ]]; then
                is_checking=1
                is_paused=1
            fi
        elif [[ "$md_resync_pos" -lt "$md_resync_size" ]]; then
            # Compatibility fallback for older Unraid versions without mdResync.
            is_checking=1
        fi
    fi

    if [[ $is_checking -eq 0 ]]; then
        if [[ "$last_uuid" != "none" ]]; then
            local completed=0
            if [[ "$last_pct" -ge 100 ]] || [[ "$md_resync_size" -gt 0 && "$md_resync_pos" -ge "$md_resync_size" ]]; then
                completed=1
            fi

            local status_word="was interrupted" event="Parity Check Interrupted" subject="Parity check interrupted"
            local desc="The parity check stopped before reaching 100% (last recorded progress: $last_pct%)."
            local importance="warning"
            if [[ $completed -eq 1 ]]; then
                status_word="completed"
                event="Parity Check Complete"
                subject="Parity check finished"
                desc="The parity check has completed."
                importance="normal"
                if [[ "$NOTIFY_ON_ERRORS" == "1" ]]; then
                    if [[ "$last_legacy" == "1" ]]; then
                        desc+=" Error count unavailable because the saved state predates error tracking."
                    else
                        local error_count sync_errors
                        sync_errors=$(ini_get "$snapshot" "sbSyncErrs")
                        if [[ "$sync_errors" =~ ^[0-9]+$ ]]; then
                            # sbSyncErrs is cumulative across checks; compare with the value at start.
                            local start_sync_errors="${last_start_line#*=}"
                            if [[ "$last_start_line" == *=* && "$start_sync_errors" =~ ^[0-9]+$ ]]; then
                                error_count=$((sync_errors - start_sync_errors))
                                (( error_count < 0 )) && error_count="$sync_errors"
                            else
                                error_count="$sync_errors"
                            fi
                        else
                            local syslog_start_line="$last_start_line"
                            [[ "$syslog_start_line" == sync=* ]] && syslog_start_line=1
                            error_count=$(count_parity_sync_errors_from_syslog "$syslog_start_line" "$last_syslog_identity")
                        fi
                        if [[ "$error_count" =~ ^[0-9]+$ && "$error_count" -gt 0 ]]; then
                            desc="The parity check completed. Unraid reported $error_count sync error(s); review the Unraid dashboard."
                            importance="alert"
                        elif [[ "$error_count" == 0 ]]; then
                            desc="The parity check completed. Unraid reported no sync errors."
                        else
                            desc="The parity check completed. Unraid's sync error count is unavailable because syslog rotated or could not be checked."
                        fi
                    fi
                fi
            fi

            log "Parity check $status_word (last recorded progress: $last_pct%)."
            write_parity_state "$STATE_FILE" "none" 0 1 0 0 0 unknown || return 1
            if [[ "$NOTIFY_ON_COMPLETION" == "1" ]]; then
                send_unraid_notify "$event" "$subject" "$desc" "$importance" || true
            fi
        fi
        log "No parity check in progress."
        return 0
    fi

    local current_pos="$md_resync_pos" total_size="$md_resync_size" current_pct=0
    current_pct=$((current_pos * 100 / total_size))
    (( current_pct > 100 )) && current_pct=100
    local action_id="${md_resync_action//[[:space:]]/_}"
    local now
    now=$(date +%s)

    local is_new_check=0
    if [[ "$last_uuid" == "none" || "$last_uuid" != "$check_uuid" ]] ||
       [[ $is_paused -eq 0 && "$current_pct" -lt "$last_pct" ]]; then
        is_new_check=1
    fi

    local check_start_line start_epoch paused_since paused_total
    if [[ $is_new_check -eq 1 ]]; then
        check_start_line=$(get_syslog_line_count)
        local initial_sync_errors
        initial_sync_errors=$(ini_get "$snapshot" "sbSyncErrs")
        if [[ "$initial_sync_errors" =~ ^[0-9]+$ ]]; then
            check_start_line="sync=$initial_sync_errors"
        fi
        last_syslog_identity=$(get_syslog_identity)
        start_epoch="$now"
        paused_since=0
        paused_total=0
        last_pct=0
        if [[ $is_paused -eq 1 ]]; then
            paused_since="$now"
            last_pct="$current_pct"
            log "Paused parity check detected at $current_pct% (position $current_pos / $total_size)."
        else
            log "New parity check detected: $current_pct% complete (position $current_pos / $total_size)."
            if [[ "$NOTIFY_ON_START" == "1" ]]; then
                send_unraid_notify "Parity Check Start" "Parity check started" \
                    "A parity check has started. Current position: $current_pct%." "normal"
            fi
        fi
    else
        check_start_line="$last_start_line"
        start_epoch="$last_start_epoch"
        paused_since="$last_paused_since"
        paused_total="$last_paused_total"
        [[ "$start_epoch" -gt 0 ]] || start_epoch="$now"
        if [[ $is_paused -eq 1 ]]; then
            [[ "$paused_since" -gt 0 ]] || paused_since="$now"
            log "Parity check paused at $current_pct% (position $current_pos / $total_size)."
        elif [[ "$paused_since" -gt 0 ]]; then
            if [[ "$now" -ge "$paused_since" ]]; then
                paused_total=$((paused_total + now - paused_since))
            fi
            paused_since=0
            log "Parity check resumed at $current_pct%."
        fi
    fi

    if [[ $is_paused -eq 0 && "$NOTIFY_ON_PROGRESS" == "1" && "$current_pct" -gt "$last_pct" ]]; then
        local milestone_step="$PROGRESS_MILESTONE_PCT"
        local last_milestone=$((last_pct / milestone_step))
        local current_milestone=$((current_pct / milestone_step))
        if [[ "$current_milestone" -gt "$last_milestone" ]]; then
            local eta_secs=0 elapsed_secs=0
            if [[ "$current_pct" -gt 0 && "$now" -ge "$start_epoch" ]]; then
                elapsed_secs=$((now - start_epoch - paused_total))
                (( elapsed_secs < 0 )) && elapsed_secs=0
                if [[ "$elapsed_secs" -gt 0 ]]; then
                    eta_secs=$((elapsed_secs * (100 - current_pct) / current_pct))
                fi
            fi
            local eta_str=""
            [[ "$eta_secs" -gt 0 ]] && eta_str=", ETA: $(format_duration "$eta_secs")"
            log "Progress milestone: $current_pct%$eta_str."
            send_unraid_notify "Parity Check Progress" "Parity check: $current_pct%" \
                "The parity check is $current_pct% complete$eta_str." "normal"
        fi
    fi

    if [[ $is_paused -eq 0 ]]; then
        last_pct="$current_pct"
        log "Parity check in progress: $current_pct%"
    fi
    write_parity_state "$STATE_FILE" "$check_uuid" "$last_pct" "$check_start_line" \
        "$start_epoch" "$paused_since" "$paused_total" "$last_syslog_identity" || return 1
    return 0
}

main "$@" || exit 1
