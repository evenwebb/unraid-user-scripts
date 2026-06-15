#!/bin/bash
#
# update-sonarr-profiles.sh
# Updates Sonarr quality profiles by show status: airing, upcoming, ended, continuing
#
# Description:
#   Assigns different quality profiles based on show status:
#   - Currently airing: next episode within AIRING_DAYS (e.g. 30)
#   - Upcoming: next episode within UPCOMING_DAYS but beyond AIRING_DAYS (e.g. 31-90)
#   - Ended: show has ended
#   - Continuing no upcoming: status continuing, no episodes within UPCOMING_DAYS
#
# Usage:
#   ./update-sonarr-profiles.sh              # Live run
#   Set DRY_RUN=1 in the script for dry run (no changes)
#
# Configuration (edit script variables below):
#   - SONARR_URL: Sonarr base URL
#   - SONARR_API_KEY: Sonarr API key
#   - AIRING_PROFILE_ID: Profile ID for currently airing shows
#   - UPCOMING_PROFILE_ID: Profile ID for upcoming shows
#   - ENDED_PROFILE_ID: Profile ID for ended shows
#   - CONTINUING_NO_UPCOMING_PROFILE_ID: Profile ID for continuing shows with nothing soon
#   - PROCESS_AIRING: "true"/"false" enable currently airing processing
#   - PROCESS_UPCOMING: "true"/"false" enable upcoming processing
#   - PROCESS_ENDED: "true"/"false" enable ended processing
#   - PROCESS_CONTINUING_NO_UPCOMING: "true"/"false" enable continuing-no-upcoming processing
#   - AIRING_DAYS: Days threshold for "currently airing"
#   - UPCOMING_DAYS: Days threshold for "upcoming" (must be >= AIRING_DAYS)
#   - DRY_RUN: 1 = dry run (no API changes), 0 = live
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#   - CURL_TIMEOUT: Seconds for curl requests (default 30)
#   - RATE_LIMIT_DELAY: Seconds between API updates (default 1)
#   - SONARR_VERIFY_SSL: 1 = verify (default), 0 = skip (self-signed certs)
#   - MAX_UPDATES_PER_RUN: Cap updates per run (0 = unlimited)
#   - LOG_VERBOSE: 1 = log each series, 0 = summary only
#   - MONITORED_ONLY: 1 = only update monitored series, 0 = all (default)
#   - NOTIFY_SCRIPT: Optional path to dynamix notify (empty = skip completion notification)
#   - TRIGGER_SEARCH: 1 = trigger Sonarr search for updated series, 0 = no (default)
#   - RETRY_COUNT: Retries for failed API calls (default 2)
#
# Logging (Unraid-friendly):
#   - Main output goes to stdout so Unraid User Scripts captures it in the GUI.
#   - When LOG_FILE is set, each log line is also appended to that file.
#   - LOG_FILE is validated: rejects paths with "..", starting with "-", or newlines.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Sonarr
SONARR_URL=""           # e.g. http://192.168.1.10:8989 (no trailing slash)
SONARR_API_KEY=""       # Settings → General → API Key

# Quality profile IDs from Sonarr (Settings → Profiles)
# Currently airing: episodes airing within AIRING_DAYS
AIRING_PROFILE_ID="1"
# Upcoming: new season/episodes within UPCOMING_DAYS (e.g. 31-90 days out)
UPCOMING_PROFILE_ID="1"
# Ended: show has ended
ENDED_PROFILE_ID="2"
# Continuing with no upcoming: status continuing, nothing soon
CONTINUING_NO_UPCOMING_PROFILE_ID="2"

# Enable/disable processing of each category (true/false)
PROCESS_AIRING="true"
PROCESS_UPCOMING="true"
PROCESS_ENDED="true"
PROCESS_CONTINUING_NO_UPCOMING="true"

# Days threshold: nextAiring within AIRING_DAYS = "currently airing"
AIRING_DAYS="30"
# Days threshold: nextAiring within UPCOMING_DAYS = "upcoming" (beyond AIRING_DAYS)
UPCOMING_DAYS="90"

# 1 = dry run (no API changes), 0 = live
DRY_RUN="0"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Curl timeout in seconds
CURL_TIMEOUT="30"

# Delay in seconds between each series update
RATE_LIMIT_DELAY="1"

# 1 = verify SSL, 0 = skip (for self-signed certs)
SONARR_VERIFY_SSL="1"

# Max series updates per run (0 = unlimited)
MAX_UPDATES_PER_RUN="0"

# 1 = log each series updated, 0 = summary only
LOG_VERBOSE="0"

# 1 = only update monitored series, 0 = all
MONITORED_ONLY="0"

# Optional: Unraid dynamix notify after run (empty = no notification)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# 1 = trigger Sonarr search for updated series, 0 = no
TRIGGER_SEARCH="0"

# Retries for failed API calls
RETRY_COUNT="2"

###############################################################################

# Validate LOG_FILE path
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

CURL_BASE=(-s -w "\n%{http_code}" --connect-timeout "$CURL_TIMEOUT" -m "$CURL_TIMEOUT")

is_safe_notify_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

send_unraid_notify() {
    local event="$1" subject="$2" description="$3"
    [[ -z "$NOTIFY_SCRIPT" || ! -x "$NOTIFY_SCRIPT" ]] && return 0
    is_safe_notify_path "$NOTIFY_SCRIPT" || return 0
    "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "normal" 2>/dev/null || true
}

sonarr_put() {
    local url="$1"
    local data="$2"
    local attempt=0
    local result
    local curl_cmd=(curl "${CURL_BASE[@]}")
    [[ "$SONARR_VERIFY_SSL" != "1" ]] && curl_cmd+=(-k)
    while [[ $attempt -le $RETRY_COUNT ]]; do
        result=$("${curl_cmd[@]}" -X PUT -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
            -d "$data" "$url" 2>/dev/null || true)
        local http_code
        http_code=$(echo "$result" | tail -n1)
        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "202" ]]; then
            return 0
        fi
        ((attempt++)) || true
        [[ $attempt -le $RETRY_COUNT ]] && sleep 2
    done
    return 1
}

main() {
    if ! command -v jq &>/dev/null; then
        log_err "jq is required but not found."
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        log_err "curl is required but not installed."
        return 1
    fi
    if [[ -z "$SONARR_URL" || -z "$SONARR_API_KEY" ]]; then
        log_err "Set SONARR_URL and SONARR_API_KEY."
        return 1
    fi
    SONARR_URL="${SONARR_URL%/}"
    if [[ "$SONARR_URL" != http://* && "$SONARR_URL" != https://* ]]; then
        log_err "SONARR_URL must start with http:// or https://"
        return 1
    fi
    if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
        log_err "DRY_RUN must be 0 or 1."
        return 1
    fi
    [[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no Sonarr changes will be made"

    local num_vars=("CURL_TIMEOUT:$CURL_TIMEOUT" "RATE_LIMIT_DELAY:$RATE_LIMIT_DELAY" \
        "RETRY_COUNT:$RETRY_COUNT" "MAX_UPDATES_PER_RUN:$MAX_UPDATES_PER_RUN" \
        "AIRING_DAYS:$AIRING_DAYS" "UPCOMING_DAYS:$UPCOMING_DAYS")
    local v
    for v in "${num_vars[@]}"; do
        local name="${v%%:*}" val="${v#*:}"
        if [[ ! "$val" =~ ^[0-9]+$ ]]; then
            log_err "$name must be a non-negative integer, got: $val"
            return 1
        fi
    done
    if [[ "$UPCOMING_DAYS" -lt "$AIRING_DAYS" ]]; then
        log_err "UPCOMING_DAYS must be >= AIRING_DAYS."
        return 1
    fi

    local profile_vars=("AIRING_PROFILE_ID:$AIRING_PROFILE_ID" "UPCOMING_PROFILE_ID:$UPCOMING_PROFILE_ID" \
        "ENDED_PROFILE_ID:$ENDED_PROFILE_ID" "CONTINUING_NO_UPCOMING_PROFILE_ID:$CONTINUING_NO_UPCOMING_PROFILE_ID")
    for v in "${profile_vars[@]}"; do
        local name="${v%%:*}" val="${v#*:}"
        if [[ ! "$val" =~ ^[0-9]+$ ]]; then
            log_err "$name must be a non-negative integer."
            return 1
        fi
    done

    if [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_notify_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi

    local process_vars=("PROCESS_AIRING:$PROCESS_AIRING" "PROCESS_UPCOMING:$PROCESS_UPCOMING" \
        "PROCESS_ENDED:$PROCESS_ENDED" "PROCESS_CONTINUING_NO_UPCOMING:$PROCESS_CONTINUING_NO_UPCOMING")
    for v in "${process_vars[@]}"; do
        local name="${v%%:*}" val="${v#*:}"
        if [[ "$val" != "true" && "$val" != "false" ]]; then
            log_err "$name must be 'true' or 'false'"
            return 1
        fi
    done

    if [[ "$MONITORED_ONLY" != "0" && "$MONITORED_ONLY" != "1" ]]; then
        log_err "MONITORED_ONLY must be 0 or 1."
        return 1
    fi
    if [[ "$LOG_VERBOSE" != "0" && "$LOG_VERBOSE" != "1" ]]; then
        log_err "LOG_VERBOSE must be 0 or 1."
        return 1
    fi
    if [[ "$TRIGGER_SEARCH" != "0" && "$TRIGGER_SEARCH" != "1" ]]; then
        log_err "TRIGGER_SEARCH must be 0 or 1."
        return 1
    fi
    if [[ "$SONARR_VERIFY_SSL" != "0" && "$SONARR_VERIFY_SSL" != "1" ]]; then
        log_err "SONARR_VERIFY_SSL must be 0 or 1."
        return 1
    fi

    if [[ "$PROCESS_AIRING" == "false" && "$PROCESS_UPCOMING" == "false" && "$PROCESS_ENDED" == "false" && "$PROCESS_CONTINUING_NO_UPCOMING" == "false" ]]; then
        log "All PROCESS_* are false. Nothing to process."
        return 0
    fi

    local now_epoch
    now_epoch=$(date +%s)
    local airing_cutoff=$((now_epoch + AIRING_DAYS * 86400))
    local upcoming_cutoff=$((now_epoch + UPCOMING_DAYS * 86400))

    local processing=""
    [[ "$PROCESS_AIRING" == "true" ]] && processing="${processing:+$processing, }airing"
    [[ "$PROCESS_UPCOMING" == "true" ]] && processing="${processing:+$processing, }upcoming"
    [[ "$PROCESS_ENDED" == "true" ]] && processing="${processing:+$processing, }ended"
    [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "true" ]] && processing="${processing:+$processing, }continuing-no-upcoming"
    log "Sonarr Quality Profile Updater - processing: $processing"

    local curl_cmd=(curl "${CURL_BASE[@]}")
    [[ "$SONARR_VERIFY_SSL" != "1" ]] && curl_cmd+=(-k)

    local series_response
    series_response=$("${curl_cmd[@]}" -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/series") || true
    local http_code
    http_code=$(echo "$series_response" | tail -n1)
    local series_json
    series_json=$(printf '%s\n' "$series_response" | sed '$d')

    if [[ "$http_code" != "200" ]] || ! echo "$series_json" | jq -e . >/dev/null 2>&1; then
        log_err "Failed to fetch series from Sonarr (HTTP $http_code or invalid JSON)."
        return 1
    fi

    local TOTAL=0
    local -a to_update=()
    while IFS=$'\t' read -r id title status next_airing cur_prof monitored; do
        [[ -z "$id" ]] && continue

        if [[ "$MONITORED_ONLY" == "1" ]] && [[ "$monitored" != "true" ]]; then
            continue
        fi

        local target_prof="" category=""
        if [[ "$status" == "ended" ]]; then
            [[ "$PROCESS_ENDED" == "true" && "$cur_prof" != "$ENDED_PROFILE_ID" ]] && target_prof="$ENDED_PROFILE_ID" && category="ended"
        elif [[ -n "$next_airing" && "$next_airing" != "null" ]]; then
            local next_epoch
            # Parse ISO date: 2025-03-15T00:00:00Z or 2025-03-15T00:00:00.000Z
            local date_str="${next_airing:0:19}"
            next_epoch=$(date -d "${date_str/T/ }" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$date_str" +%s 2>/dev/null || echo "0")
            if [[ "$next_epoch" -gt 0 ]]; then
                # nextAiring in past = between seasons, treat as continuing
                if [[ "$next_epoch" -lt "$now_epoch" ]]; then
                    [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "true" && "$cur_prof" != "$CONTINUING_NO_UPCOMING_PROFILE_ID" ]] && target_prof="$CONTINUING_NO_UPCOMING_PROFILE_ID" && category="continuing"
                elif [[ "$next_epoch" -le "$airing_cutoff" ]]; then
                    [[ "$PROCESS_AIRING" == "true" && "$cur_prof" != "$AIRING_PROFILE_ID" ]] && target_prof="$AIRING_PROFILE_ID" && category="airing"
                elif [[ "$next_epoch" -le "$upcoming_cutoff" ]]; then
                    [[ "$PROCESS_UPCOMING" == "true" && "$cur_prof" != "$UPCOMING_PROFILE_ID" ]] && target_prof="$UPCOMING_PROFILE_ID" && category="upcoming"
                else
                    [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "true" && "$cur_prof" != "$CONTINUING_NO_UPCOMING_PROFILE_ID" ]] && target_prof="$CONTINUING_NO_UPCOMING_PROFILE_ID" && category="continuing"
                fi
            else
                [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "true" && "$cur_prof" != "$CONTINUING_NO_UPCOMING_PROFILE_ID" ]] && target_prof="$CONTINUING_NO_UPCOMING_PROFILE_ID" && category="continuing"
            fi
        else
            [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "true" && "$cur_prof" != "$CONTINUING_NO_UPCOMING_PROFILE_ID" ]] && target_prof="$CONTINUING_NO_UPCOMING_PROFILE_ID" && category="continuing"
        fi

        if [[ -n "$target_prof" ]]; then
            to_update+=("${id}"$'\t'"${title}"$'\t'"${target_prof}"$'\t'"${category}")
            TOTAL=$((TOTAL + 1))
        fi
    done < <(echo "$series_json" | jq -r '.[] | [.id, (.title // ""), (.status // ""), (.nextAiring // ""), (.qualityProfileId // 0), (.monitored // false)] | @tsv')

    log "Found $TOTAL series that need a quality profile update."

    if [[ $TOTAL -eq 0 ]]; then
        log "No series need updating."
        send_unraid_notify "Update Sonarr Profiles" "Sonarr profiles" \
            "Sonarr profiles: No series needed updating."
        return 0
    fi

    local max_updates=$TOTAL
    if [[ "$MAX_UPDATES_PER_RUN" -gt 0 ]]; then
        max_updates=$MAX_UPDATES_PER_RUN
        [[ $TOTAL -gt $max_updates ]] && log "Capping at $max_updates updates (MAX_UPDATES_PER_RUN)."
    fi

    local COUNT=0 AIRING=0 UPCOMING=0 ENDED=0 CONTINUING=0 ERRORS=0
    local search_ids=()

    for entry in "${to_update[@]}"; do
        [[ $COUNT -ge $max_updates ]] && break

        local id title target_prof category
        IFS=$'\t' read -r id title target_prof category <<< "$entry"

        COUNT=$((COUNT + 1))

        if [[ "$DRY_RUN" == "0" ]]; then
            local full_series updated_series
            full_series=$("${curl_cmd[@]}" -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/series/$id" 2>/dev/null | sed '$d')
            if ! echo "$full_series" | jq -e . >/dev/null 2>&1; then
                log_err "Failed to fetch series $id for update."
                ERRORS=$((ERRORS + 1))
            else
                updated_series=$(echo "$full_series" | jq --argjson pid "$target_prof" '.qualityProfileId = $pid')
                if sonarr_put "$SONARR_URL/api/v3/series/$id" "$updated_series"; then
                    case "$category" in
                        airing) AIRING=$((AIRING + 1)) ;;
                        upcoming) UPCOMING=$((UPCOMING + 1)) ;;
                        ended) ENDED=$((ENDED + 1)) ;;
                        continuing) CONTINUING=$((CONTINUING + 1)) ;;
                    esac
                    [[ "$LOG_VERBOSE" == "1" ]] && log "  Updated: $title ($category) → profile $target_prof"
                    [[ "$TRIGGER_SEARCH" == "1" ]] && search_ids+=("$id")
                else
                    log_err "Failed to update: $title ($id)"
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        else
            case "$category" in
                airing) AIRING=$((AIRING + 1)) ;;
                upcoming) UPCOMING=$((UPCOMING + 1)) ;;
                ended) ENDED=$((ENDED + 1)) ;;
                continuing) CONTINUING=$((CONTINUING + 1)) ;;
            esac
        fi

        [[ "$RATE_LIMIT_DELAY" -gt 0 ]] && sleep "$RATE_LIMIT_DELAY"
    done

    if [[ "$DRY_RUN" == "0" && "$TRIGGER_SEARCH" == "1" && ${#search_ids[@]} -gt 0 ]]; then
        local ids_json
        ids_json=$(printf '%s\n' "${search_ids[@]}" | jq -R 'tonumber' | jq -s .)
        local cmd_body
        cmd_body=$(jq -n --argjson ids "$ids_json" '{name: "SeriesSearch", seriesIds: $ids}')
        local cmd_result
        cmd_result=$("${curl_cmd[@]}" -X POST -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
            -d "$cmd_body" "$SONARR_URL/api/v3/command" 2>/dev/null || true)
        if echo "$cmd_result" | jq -e . >/dev/null 2>&1; then
            log "Triggered search for ${#search_ids[@]} series."
        else
            log "Warning: Could not trigger Sonarr search."
        fi
    fi

    local summary="Done. Airing: $AIRING, Upcoming: $UPCOMING, Ended: $ENDED, Continuing: $CONTINUING. Errors: $ERRORS. Dry-run: $DRY_RUN"
    log "$summary"
    send_unraid_notify "Update Sonarr Profiles" "Sonarr profiles" \
        "Sonarr profiles: $AIRING airing, $UPCOMING upcoming, $ENDED ended, $CONTINUING continuing, $ERRORS errors. Dry-run: $DRY_RUN"
}

main "$@"
