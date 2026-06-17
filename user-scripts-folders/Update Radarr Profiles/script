#!/bin/bash
#
# update-radarr-profiles.sh
# Assign Radarr quality profiles by movie year window.
#
# Description:
#   Recent years → premium profile; older years → default profile.
#
# Usage:
#   ./update-radarr-profiles.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only (default), 0 = update Radarr
#
# Configuration (edit script variables below):
#   - RADARR_URL / RADARR_API_KEY
#   - CURRENT_YEAR_PROFILE_ID / OLDER_MOVIES_PROFILE_ID
#   - PROCESS_CURRENT_YEAR / PROCESS_PREVIOUS_YEAR / PREMIUM_YEARS_BACK
#   - CUSTOM_CURRENT_YEAR / CUSTOM_PREVIOUS_YEAR
#   - DRY_RUN / MONITORED_ONLY / TRIGGER_SEARCH / MAX_UPDATES_PER_RUN
#   - CURL_TIMEOUT / RATE_LIMIT_DELAY / RETRY_COUNT / RADARR_VERIFY_SSL
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

# Radarr
RADARR_URL=""           # e.g. http://192.168.1.10:7878 (no trailing slash)
RADARR_API_KEY=""       # Settings → General → API Key

# Quality profile IDs from Radarr (Settings → Profiles)
CURRENT_YEAR_PROFILE_ID="9"   # Profile for current year movies
OLDER_MOVIES_PROFILE_ID="2"   # Profile for previous year and older movies

# 1 = dry run (no API changes), 0 = live
DRY_RUN="1"

# Enable/disable processing of current and previous year (1 or 0)
PROCESS_CURRENT_YEAR="1"
PROCESS_PREVIOUS_YEAR="1"

# Premium years window:
# 0 = only current year is premium
# 1 = current year and previous year are premium
# 2 = current year and previous 2 years are premium, etc.
PREMIUM_YEARS_BACK="1"

# Optional: Override years (leave empty to auto-detect from system date)
CUSTOM_CURRENT_YEAR=""
CUSTOM_PREVIOUS_YEAR=""

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Curl timeout in seconds
CURL_TIMEOUT="30"

# Delay in seconds between each movie update (avoid hammering Radarr)
RATE_LIMIT_DELAY="1"

# 1 = verify SSL, 0 = skip (for self-signed certs)
RADARR_VERIFY_SSL="1"

# Max movie updates per run (0 = unlimited)
MAX_UPDATES_PER_RUN="0"

# 1 = log each movie updated, 0 = summary only
LOG_VERBOSE="0"

# 1 = only update monitored movies, 0 = all
MONITORED_ONLY="0"

# Optional: Unraid dynamix notify after run (empty = no notification)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# 1 = trigger Radarr search for updated movies after run, 0 = no
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
PROCESS_CURRENT_YEAR=$(_normalize_bool_flag "$PROCESS_CURRENT_YEAR")
PROCESS_PREVIOUS_YEAR=$(_normalize_bool_flag "$PROCESS_PREVIOUS_YEAR")

# Validate LOG_FILE path (reject path traversal, option-like paths, newlines)
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
    echo "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

_friendly_curl_err() {
    local msg="$1"
    msg="${msg#curl: }"
    if [[ "$msg" == *"Could not resolve host"* ]]; then
        echo "The server name could not be found — check the IP address or hostname in the script."
    elif [[ "$msg" == *"Connection refused"* ]]; then
        echo "Connection refused — is Radarr running and is the port number correct?"
    elif [[ "$msg" == *"Failed to connect"* ]]; then
        echo "Could not connect — check that Radarr is running and the URL is correct."
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
        404) log_err "Could not find ${service} at ${url} while ${task}. Check RADARR_URL in this script — it should look like http://your-server:7878 with no extra path." ;;
        000|"") log_err "Could not connect to ${service} at ${url} while ${task}. Check RADARR_URL, that Radarr is running, and that the port is correct." ;;
        *)
            if [[ -n "$body" ]] && ! printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
                log_err "${service} replied with an unexpected page (not JSON) while ${task}. The URL may be wrong — check RADARR_URL in this script."
            else
                log_err "${service} returned an error while ${task}. ${fix_hint}"
            fi
            ;;
    esac
}

# Curl base options (caller adds -k for no SSL verify if needed)
CURL_BASE=(-sS -w "\n%{http_code}" --connect-timeout "$CURL_TIMEOUT" -m "$CURL_TIMEOUT")

_radarr_curl_cmd() {
    RADARR_CURL=(curl "${CURL_BASE[@]}")
    [[ "$RADARR_VERIFY_SSL" != "1" ]] && RADARR_CURL+=(-k)
}

_radarr_http_get() {
    local path="$1" task="$2"
    local url="${RADARR_URL}${path}" resp code body curl_err fix_hint
    fix_hint="Check RADARR_URL and RADARR_API_KEY in this script (Radarr → Settings → General → API Key)."
    _radarr_curl_cmd
    curl_err=$(mktemp) || return 1
    resp=$("${RADARR_CURL[@]}" -H "X-Api-Key: $RADARR_API_KEY" -H "Accept: application/json" \
        "$url" 2>"$curl_err") || {
        _log_service_failure "Radarr" "$task" "$RADARR_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" "$fix_hint"
        rm -f "$curl_err"
        return 1
    }
    rm -f "$curl_err"
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "200" ]] || ! printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
        _log_service_failure "Radarr" "$task" "$RADARR_URL" "$code" "$body" "" "$fix_hint"
        return 1
    fi
    printf '%s' "$body"
    return 0
}

_verify_radarr_connection() {
    local payload app_name
    payload="$(_radarr_http_get "/api/v3/system/status" "checking the connection")" || return 1
    app_name=$(printf '%s' "$payload" | jq -r '.appName // empty')
    if [[ "$app_name" != "Radarr" ]]; then
        log_err "Connected but the response was not from Radarr — check RADARR_URL and RADARR_API_KEY in this script."
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

# Radarr PUT with retry
radarr_put() {
    local url="$1"
    local data="$2"
    local attempt=0 result http_code curl_err last_code="" last_curl_err=""
    local fix_hint="Check RADARR_URL and RADARR_API_KEY in this script."
    _radarr_curl_cmd
    while [[ $attempt -le $RETRY_COUNT ]]; do
        curl_err=$(mktemp) || return 1
        result=$("${RADARR_CURL[@]}" -X PUT -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
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
        _log_service_failure "Radarr" "updating a movie quality profile" "$RADARR_URL" "" "" "$last_curl_err" "$fix_hint"
    else
        _log_service_failure "Radarr" "updating a movie quality profile" "$RADARR_URL" "$last_code" "" "" "$fix_hint"
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
    if [[ -z "$RADARR_URL" || -z "$RADARR_API_KEY" ]]; then
        log_err "Radarr is not configured. Set RADARR_URL and RADARR_API_KEY at the top of this script."
        return 1
    fi
    RADARR_URL="${RADARR_URL%/}"  # Strip trailing slash for consistent URL building
    if [[ "$RADARR_URL" != http://* && "$RADARR_URL" != https://* ]]; then
        log_err "RADARR_URL must be a full web address starting with http:// or https:// (you entered: ${RADARR_URL})"
        return 1
    fi
    _verify_radarr_connection || return 1
    if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
        log_err "DRY_RUN must be 0 or 1."
        return 1
    fi
    [[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no Radarr changes will be made"

    # Validate numeric config
    local num_vars=("CURL_TIMEOUT:$CURL_TIMEOUT" "RATE_LIMIT_DELAY:$RATE_LIMIT_DELAY" \
        "RETRY_COUNT:$RETRY_COUNT" "MAX_UPDATES_PER_RUN:$MAX_UPDATES_PER_RUN" \
        "PREMIUM_YEARS_BACK:$PREMIUM_YEARS_BACK")
    local v
    for v in "${num_vars[@]}"; do
        local name="${v%%:*}" val="${v#*:}"
        if [[ ! "$val" =~ ^[0-9]+$ ]]; then
            log_err "$name must be a non-negative integer, got: $val"
            return 1
        fi
    done

    # Determine years to use (runtime, not editable config)
    if [[ -n "$CUSTOM_CURRENT_YEAR" ]]; then
        THIS_YEAR="$CUSTOM_CURRENT_YEAR"
    else
        THIS_YEAR=$(date +"%Y")
    fi

    if [[ -n "$CUSTOM_PREVIOUS_YEAR" ]]; then
        PREV_YEAR="$CUSTOM_PREVIOUS_YEAR"
    else
        PREV_YEAR=$((THIS_YEAR - 1))
    fi

    # Determine premium window start year (inclusive)
    if [[ -n "$CUSTOM_PREVIOUS_YEAR" ]]; then
        PREMIUM_MIN_YEAR="$CUSTOM_PREVIOUS_YEAR"
    else
        PREMIUM_MIN_YEAR=$((THIS_YEAR - PREMIUM_YEARS_BACK))
    fi

    if [[ -n "$CUSTOM_CURRENT_YEAR" ]] && [[ ! "$CUSTOM_CURRENT_YEAR" =~ ^[12][0-9]{3}$ ]]; then
        log_err "CUSTOM_CURRENT_YEAR must be a 4-digit year (1000-2999), got: $CUSTOM_CURRENT_YEAR"
        return 1
    fi
    if [[ -n "$CUSTOM_PREVIOUS_YEAR" ]] && [[ ! "$CUSTOM_PREVIOUS_YEAR" =~ ^[12][0-9]{3}$ ]]; then
        log_err "CUSTOM_PREVIOUS_YEAR must be a 4-digit year (1000-2999), got: $CUSTOM_PREVIOUS_YEAR"
        return 1
    fi
    if [[ ! "$CURRENT_YEAR_PROFILE_ID" =~ ^[0-9]+$ ]] || [[ ! "$OLDER_MOVIES_PROFILE_ID" =~ ^[0-9]+$ ]]; then
        log_err "CURRENT_YEAR_PROFILE_ID and OLDER_MOVIES_PROFILE_ID must be non-negative integers."
        return 1
    fi

    if [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_notify_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi

    # Validate configuration
    if [[ "$PROCESS_CURRENT_YEAR" != "0" && "$PROCESS_CURRENT_YEAR" != "1" ]]; then
        log_err "PROCESS_CURRENT_YEAR must be 0 or 1"
        return 1
    fi
    if [[ "$PROCESS_PREVIOUS_YEAR" != "0" && "$PROCESS_PREVIOUS_YEAR" != "1" ]]; then
        log_err "PROCESS_PREVIOUS_YEAR must be 0 or 1"
        return 1
    fi

    if [[ "$PROCESS_CURRENT_YEAR" == "0" && "$PROCESS_PREVIOUS_YEAR" == "0" ]]; then
        log "Both PROCESS_CURRENT_YEAR and PROCESS_PREVIOUS_YEAR are 0. Nothing to process."
        return 0
    fi

    local premium_desc
    if [[ "$PREMIUM_YEARS_BACK" -eq 0 ]]; then
        premium_desc="$THIS_YEAR"
    else
        premium_desc="${PREMIUM_MIN_YEAR}-${THIS_YEAR}"
    fi
    log "Radarr Quality Profile Updater - premium years: $premium_desc (profile $CURRENT_YEAR_PROFILE_ID), older years: profile $OLDER_MOVIES_PROFILE_ID"

    local movie_json
    movie_json=$(_radarr_http_get "/api/v3/movie" "loading the movie list") || return 1

    # Build jq filter (add monitored filter if MONITORED_ONLY=1)
    local MOVIES
    if [[ "$PROCESS_CURRENT_YEAR" == "1" && "$PROCESS_PREVIOUS_YEAR" == "1" ]]; then
        MOVIES=$(echo "$movie_json" | jq --argjson minyear "$PREMIUM_MIN_YEAR" \
               --argjson curprof "$CURRENT_YEAR_PROFILE_ID" \
               --argjson mononly "$MONITORED_ONLY" \
               '[.[] |
                  select(
                    (
                      ((.year|tonumber) >= $minyear and .qualityProfileId != $curprof) or
                      ((.year|tonumber) < $minyear and .qualityProfileId == $curprof)
                    )
                    and (if $mononly == 1 then .monitored == true else true end)
                  )
               ]')
    elif [[ "$PROCESS_CURRENT_YEAR" == "1" ]]; then
        MOVIES=$(echo "$movie_json" | jq --argjson minyear "$PREMIUM_MIN_YEAR" \
               --argjson curprof "$CURRENT_YEAR_PROFILE_ID" \
               --argjson mononly "$MONITORED_ONLY" \
               '[.[] | select((.year|tonumber) >= $minyear and .qualityProfileId != $curprof and (if $mononly == 1 then .monitored == true else true end))]')
    elif [[ "$PROCESS_PREVIOUS_YEAR" == "1" ]]; then
        MOVIES=$(echo "$movie_json" | jq --argjson minyear "$PREMIUM_MIN_YEAR" \
               --argjson curprof "$CURRENT_YEAR_PROFILE_ID" \
               --argjson mononly "$MONITORED_ONLY" \
               '[.[] | select((.year|tonumber) < $minyear and .qualityProfileId == $curprof and (if $mononly == 1 then .monitored == true else true end))]')
    else
        MOVIES="[]"
    fi

    local TOTAL
    TOTAL=$(echo "$MOVIES" | jq 'length')
    log "Found $TOTAL movies that need a quality profile update."

    if [[ "$TOTAL" -eq 0 ]]; then
        log "No movies need updating."
        send_unraid_notify "Update Radarr Profiles" "Radarr profiles" \
            "Radarr profiles: No movies needed updating."
        return 0
    fi

    local max_updates=$TOTAL
    if [[ "$MAX_UPDATES_PER_RUN" -gt 0 ]]; then
        max_updates=$MAX_UPDATES_PER_RUN
        [[ $TOTAL -gt $max_updates ]] && log "Capping at $max_updates updates (MAX_UPDATES_PER_RUN)."
    fi

    local COUNT=0 CHANGED=0 REVERTED=0 ERRORS=0
    local target_total=$max_updates
    [[ $TOTAL -lt $target_total ]] && target_total=$TOTAL
    local start_epoch
    start_epoch=$(date +%s)
    local progress_every=10
    local search_ids=()
    local TMP_FILE
    TMP_FILE=$(mktemp) || { log_err "Failed to create temp file"; return 1; }
    trap "rm -f '${TMP_FILE}'" EXIT
    echo "$MOVIES" | jq -c '.[]' > "$TMP_FILE"

    while IFS=$'\t' read -r MOVIE_ID MOVIE_TITLE MOVIE_YEAR PROFILE_ID; do
        [[ $COUNT -ge $max_updates ]] && break

        COUNT=$((COUNT + 1))

        if [[ "$LOG_VERBOSE" != "1" ]]; then
            if [[ $COUNT -eq 1 ]]; then
                log "Working... progress will update every $progress_every movies."
            elif [[ $((COUNT % progress_every)) -eq 0 || $COUNT -eq $target_total ]]; then
                local now_epoch elapsed rate eta
                now_epoch=$(date +%s)
                elapsed=$((now_epoch - start_epoch))
                if [[ $elapsed -le 0 ]]; then
                    log "Progress: $COUNT/$target_total (updated=$CHANGED, reverted=$REVERTED, errors=$ERRORS)"
                else
                    rate=$((COUNT / elapsed))
                    if [[ $rate -le 0 ]]; then
                        log "Progress: $COUNT/$target_total (updated=$CHANGED, reverted=$REVERTED, errors=$ERRORS) elapsed=${elapsed}s"
                    else
                        eta=$(((target_total - COUNT) / rate))
                        log "Progress: $COUNT/$target_total (updated=$CHANGED, reverted=$REVERTED, errors=$ERRORS) elapsed=${elapsed}s eta=${eta}s"
                    fi
                fi
            fi
        fi

        if [[ "$PROCESS_CURRENT_YEAR" == "1" && "$MOVIE_YEAR" -ge "$PREMIUM_MIN_YEAR" && "$PROFILE_ID" -ne "$CURRENT_YEAR_PROFILE_ID" ]]; then
            if [[ "$DRY_RUN" == "0" ]]; then
                local FULL_MOVIE UPDATED_MOVIE
                FULL_MOVIE=$(_radarr_http_get "/api/v3/movie/$MOVIE_ID" "loading details for '$MOVIE_TITLE'") || { ERRORS=$((ERRORS + 1)); continue; }
                UPDATED_MOVIE=$(echo "$FULL_MOVIE" | jq --argjson pid "$CURRENT_YEAR_PROFILE_ID" '.qualityProfileId = $pid')
                if radarr_put "$RADARR_URL/api/v3/movie/$MOVIE_ID" "$UPDATED_MOVIE"; then
                    CHANGED=$((CHANGED + 1))
                    [[ "$LOG_VERBOSE" == "1" ]] && log "  Updated: $MOVIE_TITLE ($MOVIE_YEAR) → premium profile"
                    [[ "$TRIGGER_SEARCH" == "1" ]] && search_ids+=("$MOVIE_ID")
                else
                    ERRORS=$((ERRORS + 1))
                fi
            else
                CHANGED=$((CHANGED + 1))
            fi
            [[ "$RATE_LIMIT_DELAY" -gt 0 ]] && sleep "$RATE_LIMIT_DELAY"
        fi

        if [[ "$PROCESS_PREVIOUS_YEAR" == "1" && "$MOVIE_YEAR" -lt "$PREMIUM_MIN_YEAR" && "$PROFILE_ID" -eq "$CURRENT_YEAR_PROFILE_ID" ]]; then
            if [[ "$DRY_RUN" == "0" ]]; then
                local FULL_MOVIE UPDATED_MOVIE
                FULL_MOVIE=$(_radarr_http_get "/api/v3/movie/$MOVIE_ID" "loading details for '$MOVIE_TITLE'") || { ERRORS=$((ERRORS + 1)); continue; }
                UPDATED_MOVIE=$(echo "$FULL_MOVIE" | jq --argjson pid "$OLDER_MOVIES_PROFILE_ID" '.qualityProfileId = $pid')
                if radarr_put "$RADARR_URL/api/v3/movie/$MOVIE_ID" "$UPDATED_MOVIE"; then
                    REVERTED=$((REVERTED + 1))
                    [[ "$LOG_VERBOSE" == "1" ]] && log "  Reverted: $MOVIE_TITLE ($MOVIE_YEAR) → older profile"
                else
                    ERRORS=$((ERRORS + 1))
                fi
            else
                REVERTED=$((REVERTED + 1))
            fi
            [[ "$RATE_LIMIT_DELAY" -gt 0 ]] && sleep "$RATE_LIMIT_DELAY"
        fi
    done < <(jq -r '[.id, (.title // ""), (.year // 0), (.qualityProfileId // 0)] | @tsv' "$TMP_FILE")

    rm -f "$TMP_FILE"
    trap - EXIT

    # Trigger search for updated movies
    if [[ "$DRY_RUN" == "0" && "$TRIGGER_SEARCH" == "1" && ${#search_ids[@]} -gt 0 ]]; then
        local ids_json
        ids_json=$(printf '%s\n' "${search_ids[@]}" | jq -R 'tonumber' | jq -s .)
        local cmd_body
        cmd_body=$(jq -n --argjson ids "$ids_json" '{name: "MoviesSearch", movieIds: $ids}')
        local cmd_result code curl_err=""
        _radarr_curl_cmd
        curl_err=$(mktemp)
        if [[ -n "$curl_err" ]]; then
            cmd_result=$("${RADARR_CURL[@]}" -X POST -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
                -d "$cmd_body" "$RADARR_URL/api/v3/command" 2>"$curl_err") || {
                _log_service_failure "Radarr" "triggering a search for updated movies" "$RADARR_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" \
                    "Check RADARR_URL and RADARR_API_KEY in this script."
            }
            rm -f "$curl_err"
            code=$(echo "$cmd_result" | tail -n1)
            if [[ "$code" == 2* ]] && printf '%s' "$(echo "$cmd_result" | sed '$d')" | jq -e . >/dev/null 2>&1; then
                log "Triggered search for ${#search_ids[@]} movie(s)."
            elif [[ -n "$cmd_result" ]]; then
                _log_service_failure "Radarr" "triggering a search for updated movies" "$RADARR_URL" "$code" "$(echo "$cmd_result" | sed '$d')" "" \
                    "Check RADARR_URL and RADARR_API_KEY in this script."
            fi
        fi
    fi

    local summary="Done. Updated to current year profile: $CHANGED. Reverted to default: $REVERTED. Errors: $ERRORS. Dry-run: $DRY_RUN"
    log "$summary"
    send_unraid_notify "Update Radarr Profiles" "Radarr profiles" \
        "Radarr profiles: $CHANGED updated, $REVERTED reverted, $ERRORS errors. Dry-run: $DRY_RUN"
}

main "$@"
