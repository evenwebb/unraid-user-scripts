#!/bin/bash
#
# update-radarr-profiles.sh
# Updates Radarr quality profiles by year window: recent years → premium profile, older years → default profile
#
# Description:
#   For movies in the premium window (current year back PREMIUM_YEARS_BACK years):
#   sets quality profile to a "premium" profile (e.g. higher quality).
#   For movies older than the premium window: reverts from that profile back to
#   the default. Run periodically (e.g. monthly) or after adding many movies.
#
# Usage:
#   ./update-radarr-profiles.sh              # Live run
#   Set DRY_RUN=1 in the script for dry run (no changes)
#
# Configuration (edit script variables below):
#   - RADARR_URL: Radarr base URL
#   - RADARR_API_KEY: Radarr API key
#   - CURRENT_YEAR_PROFILE_ID: Quality profile ID for premium window movies
#   - OLDER_MOVIES_PROFILE_ID: Quality profile ID for older movies
#   - PROCESS_CURRENT_YEAR: Apply premium profile to movies in the premium window ("true"/"false")
#   - PROCESS_PREVIOUS_YEAR: Revert premium profile for movies older than the premium window ("true"/"false")
#   - PREMIUM_YEARS_BACK: Number of years back (0=current year only, 1=current+previous, etc.)
#   - CUSTOM_CURRENT_YEAR: Optional override for "current year" (empty = auto-detect)
#   - CUSTOM_PREVIOUS_YEAR: Optional override for premium window start year (empty = auto-detect)
#   - DRY_RUN: 1 = dry run (no API changes), 0 = live
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#   - CURL_TIMEOUT: Seconds for curl requests (default 30)
#   - RATE_LIMIT_DELAY: Seconds between API updates (default 1)
#   - RADARR_VERIFY_SSL: 1 = verify (default), 0 = skip (self-signed certs)
#   - MAX_UPDATES_PER_RUN: Cap updates per run (0 = unlimited)
#   - LOG_VERBOSE: 1 = log each movie, 0 = summary only
#   - MONITORED_ONLY: 1 = only update monitored movies, 0 = all (default)
#   - PUSHOVER_USER_KEY: Optional Pushover user key (requires PUSHOVER_APP_TOKEN)
#   - PUSHOVER_APP_TOKEN: Optional Pushover app token (requires PUSHOVER_USER_KEY)
#   - TRIGGER_SEARCH: 1 = trigger Radarr search for updated movies, 0 = no (default)
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

# Radarr
RADARR_URL=""           # e.g. http://192.168.1.10:7878 (no trailing slash)
RADARR_API_KEY=""       # Settings → General → API Key

# Quality profile IDs from Radarr (Settings → Profiles)
CURRENT_YEAR_PROFILE_ID="9"   # Profile for current year movies
OLDER_MOVIES_PROFILE_ID="2"   # Profile for previous year and older movies

# 1 = dry run (no API changes), 0 = live
DRY_RUN="0"

# Enable/disable processing of current and previous year (true/false)
PROCESS_CURRENT_YEAR="true"
PROCESS_PREVIOUS_YEAR="true"

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

# Optional: Pushover notification (both required when set)
PUSHOVER_USER_KEY=""
PUSHOVER_APP_TOKEN=""

# 1 = trigger Radarr search for updated movies after run, 0 = no
TRIGGER_SEARCH="0"

# Retries for failed API calls
RETRY_COUNT="2"

###############################################################################

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

# Curl base options (caller adds -k for no SSL verify if needed)
CURL_BASE=(-s -w "\n%{http_code}" --connect-timeout "$CURL_TIMEOUT" -m "$CURL_TIMEOUT")

send_pushover() {
    local message="$1"
    [[ -z "$PUSHOVER_APP_TOKEN" || -z "$PUSHOVER_USER_KEY" ]] && return 0
    command -v curl >/dev/null 2>&1 || return 0
    curl -s --connect-timeout 10 -m "$CURL_TIMEOUT" \
        -F "token=$PUSHOVER_APP_TOKEN" -F "user=$PUSHOVER_USER_KEY" -F "message=$message" \
        https://api.pushover.net/1/messages.json >/dev/null 2>&1 || true
}

# Radarr PUT with retry
radarr_put() {
    local url="$1"
    local data="$2"
    local attempt=0
    local result
    local curl_cmd=(curl "${CURL_BASE[@]}")
    [[ "$RADARR_VERIFY_SSL" != "1" ]] && curl_cmd+=(-k)
    while [[ $attempt -le $RETRY_COUNT ]]; do
        result=$("${curl_cmd[@]}" -X PUT -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
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
    if [[ -z "$RADARR_URL" || -z "$RADARR_API_KEY" ]]; then
        log_err "Set RADARR_URL and RADARR_API_KEY."
        return 1
    fi
    RADARR_URL="${RADARR_URL%/}"  # Strip trailing slash for consistent URL building
    if [[ "$RADARR_URL" != http://* && "$RADARR_URL" != https://* ]]; then
        log_err "RADARR_URL must start with http:// or https://"
        return 1
    fi
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

    # Validate Pushover (both or neither)
    if [[ -n "$PUSHOVER_APP_TOKEN" ]] && [[ -z "$PUSHOVER_USER_KEY" ]]; then
        log "Warning: PUSHOVER_APP_TOKEN set but PUSHOVER_USER_KEY missing. Notifications disabled."
        PUSHOVER_USER_KEY=""
        PUSHOVER_APP_TOKEN=""
    elif [[ -z "$PUSHOVER_APP_TOKEN" ]] && [[ -n "$PUSHOVER_USER_KEY" ]]; then
        log "Warning: PUSHOVER_USER_KEY set but PUSHOVER_APP_TOKEN missing. Notifications disabled."
        PUSHOVER_USER_KEY=""
        PUSHOVER_APP_TOKEN=""
    fi

    # Validate configuration
    if [[ "$PROCESS_CURRENT_YEAR" != "true" && "$PROCESS_CURRENT_YEAR" != "false" ]]; then
        log_err "PROCESS_CURRENT_YEAR must be 'true' or 'false'"
        return 1
    fi
    if [[ "$PROCESS_PREVIOUS_YEAR" != "true" && "$PROCESS_PREVIOUS_YEAR" != "false" ]]; then
        log_err "PROCESS_PREVIOUS_YEAR must be 'true' or 'false'"
        return 1
    fi

    if [[ "$PROCESS_CURRENT_YEAR" == "false" && "$PROCESS_PREVIOUS_YEAR" == "false" ]]; then
        log "Both PROCESS_CURRENT_YEAR and PROCESS_PREVIOUS_YEAR are false. Nothing to process."
        return 0
    fi

    local premium_desc
    if [[ "$PREMIUM_YEARS_BACK" -eq 0 ]]; then
        premium_desc="$THIS_YEAR"
    else
        premium_desc="${PREMIUM_MIN_YEAR}-${THIS_YEAR}"
    fi
    log "Radarr Quality Profile Updater - premium years: $premium_desc (profile $CURRENT_YEAR_PROFILE_ID), older years: profile $OLDER_MOVIES_PROFILE_ID"

    local curl_cmd=(curl "${CURL_BASE[@]}")
    [[ "$RADARR_VERIFY_SSL" != "1" ]] && curl_cmd+=(-k)

    # Fetch movies from Radarr
    local movie_response
    movie_response=$("${curl_cmd[@]}" -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/movie") || true
    local http_code
    http_code=$(echo "$movie_response" | tail -n1)
    local movie_json
    movie_json=$(echo "$movie_response" | sed '$d')

    if [[ "$http_code" != "200" ]] || ! echo "$movie_json" | jq -e . >/dev/null 2>&1; then
        log_err "Failed to fetch movies from Radarr (HTTP $http_code or invalid JSON)."
        return 1
    fi

    # Build jq filter (add monitored filter if MONITORED_ONLY=1)
    local MOVIES
    if [[ "$PROCESS_CURRENT_YEAR" == "true" && "$PROCESS_PREVIOUS_YEAR" == "true" ]]; then
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
    elif [[ "$PROCESS_CURRENT_YEAR" == "true" ]]; then
        MOVIES=$(echo "$movie_json" | jq --argjson minyear "$PREMIUM_MIN_YEAR" \
               --argjson curprof "$CURRENT_YEAR_PROFILE_ID" \
               --argjson mononly "$MONITORED_ONLY" \
               '[.[] | select((.year|tonumber) >= $minyear and .qualityProfileId != $curprof and (if $mononly == 1 then .monitored == true else true end))]')
    elif [[ "$PROCESS_PREVIOUS_YEAR" == "true" ]]; then
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
        send_pushover "Radarr profiles: No movies needed updating."
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
    echo "$MOVIES" | jq -c '.[]' > "$TMP_FILE"

    while read -r MOVIE; do
        [[ $COUNT -ge $max_updates ]] && break

        COUNT=$((COUNT + 1))
        local MOVIE_ID MOVIE_TITLE MOVIE_YEAR PROFILE_ID
        MOVIE_ID=$(echo "$MOVIE" | jq '.id')
        MOVIE_TITLE=$(echo "$MOVIE" | jq -r '.title')
        MOVIE_YEAR=$(echo "$MOVIE" | jq '.year')
        PROFILE_ID=$(echo "$MOVIE" | jq '.qualityProfileId')

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

        if [[ "$PROCESS_CURRENT_YEAR" == "true" && "$MOVIE_YEAR" -ge "$PREMIUM_MIN_YEAR" && "$PROFILE_ID" -ne "$CURRENT_YEAR_PROFILE_ID" ]]; then
            if [[ "$DRY_RUN" == "0" ]]; then
                local FULL_MOVIE UPDATED_MOVIE
                FULL_MOVIE=$("${curl_cmd[@]}" -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/movie/$MOVIE_ID" 2>/dev/null | sed '$d')
                UPDATED_MOVIE=$(echo "$FULL_MOVIE" | jq --argjson pid "$CURRENT_YEAR_PROFILE_ID" '.qualityProfileId = $pid')
                if radarr_put "$RADARR_URL/api/v3/movie/$MOVIE_ID" "$UPDATED_MOVIE"; then
                    [[ "$LOG_VERBOSE" == "1" ]] && log "  Updated: $MOVIE_TITLE ($MOVIE_YEAR) → premium profile"
                    [[ "$TRIGGER_SEARCH" == "1" ]] && search_ids+=("$MOVIE_ID")
                else
                    log_err "Failed to update: $MOVIE_TITLE ($MOVIE_ID)"
                    ERRORS=$((ERRORS + 1))
                fi
            fi
            CHANGED=$((CHANGED + 1))
            [[ "$RATE_LIMIT_DELAY" -gt 0 ]] && sleep "$RATE_LIMIT_DELAY"
        fi

        if [[ "$PROCESS_PREVIOUS_YEAR" == "true" && "$MOVIE_YEAR" -lt "$PREMIUM_MIN_YEAR" && "$PROFILE_ID" -eq "$CURRENT_YEAR_PROFILE_ID" ]]; then
            if [[ "$DRY_RUN" == "0" ]]; then
                local FULL_MOVIE UPDATED_MOVIE
                FULL_MOVIE=$("${curl_cmd[@]}" -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/movie/$MOVIE_ID" 2>/dev/null | sed '$d')
                UPDATED_MOVIE=$(echo "$FULL_MOVIE" | jq --argjson pid "$OLDER_MOVIES_PROFILE_ID" '.qualityProfileId = $pid')
                if radarr_put "$RADARR_URL/api/v3/movie/$MOVIE_ID" "$UPDATED_MOVIE"; then
                    [[ "$LOG_VERBOSE" == "1" ]] && log "  Reverted: $MOVIE_TITLE ($MOVIE_YEAR) → older profile"
                else
                    log_err "Failed to revert: $MOVIE_TITLE ($MOVIE_ID)"
                    ERRORS=$((ERRORS + 1))
                fi
            fi
            REVERTED=$((REVERTED + 1))
            [[ "$RATE_LIMIT_DELAY" -gt 0 ]] && sleep "$RATE_LIMIT_DELAY"
        fi
    done < "$TMP_FILE"

    rm -f "$TMP_FILE"

    # Trigger search for updated movies
    if [[ "$DRY_RUN" == "0" && "$TRIGGER_SEARCH" == "1" && ${#search_ids[@]} -gt 0 ]]; then
        local ids_json
        ids_json=$(printf '%s\n' "${search_ids[@]}" | jq -R 'tonumber' | jq -s .)
        local cmd_body
        cmd_body=$(jq -n --argjson ids "$ids_json" '{name: "MoviesSearch", movieIds: $ids}')
        local cmd_result
        cmd_result=$("${curl_cmd[@]}" -X POST -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
            -d "$cmd_body" "$RADARR_URL/api/v3/command" 2>/dev/null || true)
        if echo "$cmd_result" | jq -e . >/dev/null 2>&1; then
            log "Triggered search for ${#search_ids[@]} movie(s)."
        else
            log "Warning: Could not trigger Radarr search."
        fi
    fi

    local summary="Done. Updated to current year profile: $CHANGED. Reverted to default: $REVERTED. Errors: $ERRORS. Dry-run: $DRY_RUN"
    log "$summary"
    send_pushover "Radarr profiles: $CHANGED updated, $REVERTED reverted. Dry-run: $DRY_RUN"
}

main "$@"
