#!/bin/bash
#
# update-sonarr-profiles.sh
# Assign Sonarr quality profiles by show status (airing, upcoming, ended, continuing).
#
# Description:
#   Uses nextAiring and status to pick the target profile.
#
# Usage:
#   ./update-sonarr-profiles.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only (default), 0 = update Sonarr
#
# Configuration (edit script variables below):
#   - SONARR_URL / SONARR_API_KEY
#   - AIRING_PROFILE_ID / UPCOMING_PROFILE_ID / ENDED_PROFILE_ID / CONTINUING_NO_UPCOMING_PROFILE_ID
#   - PROCESS_AIRING / PROCESS_UPCOMING / PROCESS_ENDED / PROCESS_CONTINUING_NO_UPCOMING: 1 or 0
#   - AIRING_DAYS / UPCOMING_DAYS
#   - DRY_RUN / MONITORED_ONLY / TRIGGER_SEARCH / MAX_UPDATES_PER_RUN
#   - CURL_TIMEOUT / RATE_LIMIT_DELAY / RETRY_COUNT / SONARR_VERIFY_SSL
#   - LOG_VERBOSE / LOG_FILE / NOTIFY_SCRIPT
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
PROCESS_AIRING="1"
PROCESS_UPCOMING="1"
PROCESS_ENDED="1"
PROCESS_CONTINUING_NO_UPCOMING="1"

# Days threshold: nextAiring within AIRING_DAYS = "currently airing"
AIRING_DAYS="30"
# Days threshold: nextAiring within UPCOMING_DAYS = "upcoming" (beyond AIRING_DAYS)
UPCOMING_DAYS="90"

# 1 = dry run (no API changes), 0 = live
DRY_RUN="1"

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

_normalize_bool_flag() {
    case "$1" in
        true|True|TRUE|1) echo "1" ;;
        false|False|FALSE|0) echo "0" ;;
        *) echo "$1" ;;
    esac
}
PROCESS_AIRING=$(_normalize_bool_flag "$PROCESS_AIRING")
PROCESS_UPCOMING=$(_normalize_bool_flag "$PROCESS_UPCOMING")
PROCESS_ENDED=$(_normalize_bool_flag "$PROCESS_ENDED")
PROCESS_CONTINUING_NO_UPCOMING=$(_normalize_bool_flag "$PROCESS_CONTINUING_NO_UPCOMING")

# Validate LOG_FILE path
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

_friendly_curl_err() {
    local msg="$1"
    msg="${msg#curl: }"
    if [[ "$msg" == *"Could not resolve host"* ]]; then
        echo "The server name could not be found — check the IP address or hostname in the script."
    elif [[ "$msg" == *"Connection refused"* ]]; then
        echo "Connection refused — is Sonarr running and is the port number correct?"
    elif [[ "$msg" == *"Failed to connect"* ]]; then
        echo "Could not connect — check that Sonarr is running and the URL is correct."
    elif [[ "$msg" == *"timed out"* ]] || [[ "$msg" == *"Timeout"* ]]; then
        echo "The connection timed out — check the URL and network."
    elif [[ "$msg" == *"Unauthorized"* ]] || [[ "$msg" == *"401"* ]]; then
        echo "Login was rejected — wrong API key."
    else
        echo "$msg"
    fi
}

_log_service_failure() {
    local service="$1" task="$2" url="$3" code="$4" body="$5" curl_err="${6:-}" fix_hint="${7:-Check the URL and API key in this script.}"
    if [[ -n "$curl_err" ]]; then
        log_err "Could not reach ${service} while ${task}. $(_friendly_curl_err "$curl_err") ${fix_hint}"
        return
    fi
    case "$code" in
        401) log_err "Wrong API key for ${service} while ${task}. ${fix_hint}" ;;
        403) log_err "${service} refused access while ${task}. ${fix_hint}" ;;
        404) log_err "Could not find ${service} at ${url} while ${task}. Check SONARR_URL in this script — it should look like http://your-server:8989 with no extra path." ;;
        000|"") log_err "Could not connect to ${service} at ${url} while ${task}. Check SONARR_URL, that Sonarr is running, and that the port is correct." ;;
        *)
            if [[ -n "$body" ]] && ! printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
                log_err "${service} replied with an unexpected page (not JSON) while ${task}. The URL may be wrong — check SONARR_URL in this script."
            else
                log_err "${service} returned an error while ${task}. ${fix_hint}"
            fi
            ;;
    esac
}

CURL_BASE=(-sS -w "\n%{http_code}" --connect-timeout "$CURL_TIMEOUT" -m "$CURL_TIMEOUT")

_sonarr_curl_cmd() {
    SONARR_CURL=(curl "${CURL_BASE[@]}")
    [[ "$SONARR_VERIFY_SSL" != "1" ]] && SONARR_CURL+=(-k)
}

_sonarr_http_get() {
    local path="$1" task="$2"
    local url="${SONARR_URL}${path}" resp code body curl_err fix_hint
    fix_hint="Check SONARR_URL and SONARR_API_KEY in this script (Sonarr → Settings → General → API Key)."
    _sonarr_curl_cmd
    curl_err=$(mktemp) || return 1
    resp=$("${SONARR_CURL[@]}" -H "X-Api-Key: $SONARR_API_KEY" -H "Accept: application/json" \
        "$url" 2>"$curl_err") || {
        _log_service_failure "Sonarr" "$task" "$SONARR_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" "$fix_hint"
        rm -f "$curl_err"
        return 1
    }
    rm -f "$curl_err"
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "200" ]] || ! printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
        _log_service_failure "Sonarr" "$task" "$SONARR_URL" "$code" "$body" "" "$fix_hint"
        return 1
    fi
    printf '%s' "$body"
    return 0
}

_verify_sonarr_connection() {
    local payload app_name
    payload="$(_sonarr_http_get "/api/v3/system/status" "checking the connection")" || return 1
    app_name=$(printf '%s' "$payload" | jq -r '.appName // empty')
    if [[ "$app_name" != "Sonarr" ]]; then
        log_err "Connected but the response was not from Sonarr — check SONARR_URL and SONARR_API_KEY in this script."
        return 1
    fi
    return 0
}

is_safe_notify_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

send_unraid_notify() {
    local event="$1" subject="$2" description="$3"
    [[ -z "$NOTIFY_SCRIPT" || ! -x "$NOTIFY_SCRIPT" ]] && return 0
    if ! is_safe_notify_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path is not allowed. Check NOTIFY_SCRIPT in this script."
        return 1
    fi
    if ! "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "normal"; then
        log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script (currently: $NOTIFY_SCRIPT)."
        return 1
    fi
}

sonarr_put() {
    local url="$1"
    local data="$2"
    local attempt=0 result http_code curl_err last_code="" last_curl_err=""
    local fix_hint="Check SONARR_URL and SONARR_API_KEY in this script."
    _sonarr_curl_cmd
    while [[ $attempt -le $RETRY_COUNT ]]; do
        curl_err=$(mktemp) || return 1
        result=$("${SONARR_CURL[@]}" -X PUT -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
            -d "$data" "$url" 2>"$curl_err") || last_curl_err=$(tr '\n' ' ' <"$curl_err")
        rm -f "$curl_err"
        http_code=$(echo "$result" | tail -n1)
        last_code="$http_code"
        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "202" ]]; then
            return 0
        fi
        ((attempt++)) || true
        [[ $attempt -le $RETRY_COUNT ]] && sleep 2
    done
    if [[ -n "$last_curl_err" ]]; then
        _log_service_failure "Sonarr" "updating a series quality profile" "$SONARR_URL" "" "" "$last_curl_err" "$fix_hint"
    else
        _log_service_failure "Sonarr" "updating a series quality profile" "$SONARR_URL" "$last_code" "" "" "$fix_hint"
    fi
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
        log_err "Sonarr is not configured. Set SONARR_URL and SONARR_API_KEY at the top of this script."
        return 1
    fi
    SONARR_URL="${SONARR_URL%/}"
    if [[ "$SONARR_URL" != http://* && "$SONARR_URL" != https://* ]]; then
        log_err "SONARR_URL must be a full web address starting with http:// or https:// (you entered: ${SONARR_URL})"
        return 1
    fi
    _verify_sonarr_connection || return 1
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
        if [[ "$val" != "0" && "$val" != "1" ]]; then
            log_err "$name must be 0 or 1"
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

    if [[ "$PROCESS_AIRING" == "0" && "$PROCESS_UPCOMING" == "0" && "$PROCESS_ENDED" == "0" && "$PROCESS_CONTINUING_NO_UPCOMING" == "0" ]]; then
        log "All PROCESS_* are 0. Nothing to process."
        return 0
    fi

    local now_epoch
    now_epoch=$(date +%s)
    local airing_cutoff=$((now_epoch + AIRING_DAYS * 86400))
    local upcoming_cutoff=$((now_epoch + UPCOMING_DAYS * 86400))

    local processing=""
    [[ "$PROCESS_AIRING" == "1" ]] && processing="${processing:+$processing, }airing"
    [[ "$PROCESS_UPCOMING" == "1" ]] && processing="${processing:+$processing, }upcoming"
    [[ "$PROCESS_ENDED" == "1" ]] && processing="${processing:+$processing, }ended"
    [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "1" ]] && processing="${processing:+$processing, }continuing-no-upcoming"
    log "Sonarr Quality Profile Updater - processing: $processing"

    local series_json
    series_json=$(_sonarr_http_get "/api/v3/series" "loading the series list") || return 1

    local TOTAL=0
    local -a to_update=()
    while IFS=$'\t' read -r id title status next_airing cur_prof monitored; do
        [[ -z "$id" ]] && continue

        if [[ "$MONITORED_ONLY" == "1" ]] && [[ "$monitored" != "true" ]]; then
            continue
        fi

        local target_prof="" category=""
        if [[ "$status" == "ended" ]]; then
            [[ "$PROCESS_ENDED" == "1" && "$cur_prof" != "$ENDED_PROFILE_ID" ]] && target_prof="$ENDED_PROFILE_ID" && category="ended"
        elif [[ -n "$next_airing" && "$next_airing" != "null" ]]; then
            local next_epoch
            # Parse ISO date: 2025-03-15T00:00:00Z or 2025-03-15T00:00:00.000Z
            local date_str="${next_airing:0:19}"
            next_epoch=$(date -d "${date_str/T/ }" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$date_str" +%s 2>/dev/null || echo "0")
            if [[ "$next_epoch" -gt 0 ]]; then
                # nextAiring in past = between seasons, treat as continuing
                if [[ "$next_epoch" -lt "$now_epoch" ]]; then
                    [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "1" && "$cur_prof" != "$CONTINUING_NO_UPCOMING_PROFILE_ID" ]] && target_prof="$CONTINUING_NO_UPCOMING_PROFILE_ID" && category="continuing"
                elif [[ "$next_epoch" -le "$airing_cutoff" ]]; then
                    [[ "$PROCESS_AIRING" == "1" && "$cur_prof" != "$AIRING_PROFILE_ID" ]] && target_prof="$AIRING_PROFILE_ID" && category="airing"
                elif [[ "$next_epoch" -le "$upcoming_cutoff" ]]; then
                    [[ "$PROCESS_UPCOMING" == "1" && "$cur_prof" != "$UPCOMING_PROFILE_ID" ]] && target_prof="$UPCOMING_PROFILE_ID" && category="upcoming"
                else
                    [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "1" && "$cur_prof" != "$CONTINUING_NO_UPCOMING_PROFILE_ID" ]] && target_prof="$CONTINUING_NO_UPCOMING_PROFILE_ID" && category="continuing"
                fi
            else
                [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "1" && "$cur_prof" != "$CONTINUING_NO_UPCOMING_PROFILE_ID" ]] && target_prof="$CONTINUING_NO_UPCOMING_PROFILE_ID" && category="continuing"
            fi
        else
            [[ "$PROCESS_CONTINUING_NO_UPCOMING" == "1" && "$cur_prof" != "$CONTINUING_NO_UPCOMING_PROFILE_ID" ]] && target_prof="$CONTINUING_NO_UPCOMING_PROFILE_ID" && category="continuing"
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
            full_series=$(_sonarr_http_get "/api/v3/series/$id" "loading details for '$title'") || { ERRORS=$((ERRORS + 1)); continue; }
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
                ERRORS=$((ERRORS + 1))
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
        local cmd_result code curl_err
        _sonarr_curl_cmd
        curl_err=$(mktemp)
        if [[ -n "$curl_err" ]]; then
            cmd_result=$("${SONARR_CURL[@]}" -X POST -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
                -d "$cmd_body" "$SONARR_URL/api/v3/command" 2>"$curl_err") || {
                _log_service_failure "Sonarr" "triggering a search for updated series" "$SONARR_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" \
                    "Check SONARR_URL and SONARR_API_KEY in this script."
            }
            rm -f "$curl_err"
            code=$(echo "$cmd_result" | tail -n1)
            if [[ "$code" == 2* ]] && printf '%s' "$(echo "$cmd_result" | sed '$d')" | jq -e . >/dev/null 2>&1; then
                log "Triggered search for ${#search_ids[@]} series."
            elif [[ -n "$cmd_result" ]]; then
                _log_service_failure "Sonarr" "triggering a search for updated series" "$SONARR_URL" "$code" "$(echo "$cmd_result" | sed '$d')" "" \
                    "Check SONARR_URL and SONARR_API_KEY in this script."
            fi
        fi
    fi

    local summary="Done. Airing: $AIRING, Upcoming: $UPCOMING, Ended: $ENDED, Continuing: $CONTINUING. Errors: $ERRORS. Dry-run: $DRY_RUN"
    log "$summary"
    send_unraid_notify "Update Sonarr Profiles" "Sonarr profiles" \
        "Sonarr profiles: $AIRING airing, $UPCOMING upcoming, $ENDED ended, $CONTINUING continuing, $ERRORS errors. Dry-run: $DRY_RUN"
}

main "$@"
