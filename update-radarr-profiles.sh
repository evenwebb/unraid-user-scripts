#!/bin/bash
#
# update-radarr-profiles.sh
# Updates Radarr quality profiles by year: current year → high-quality profile, previous year → default profile
#
# Description:
#   For movies from the current year: sets quality profile to a "current year" profile
#   (e.g. higher quality). For movies from the previous year: reverts from that
#   profile back to the default. Run periodically (e.g. monthly) or after adding
#   many movies.
#
# Usage:
#   ./update-radarr-profiles.sh              # Live run
#   DRY_RUN=1 ./update-radarr-profiles.sh   # Dry run (no changes)
#
# Configuration:
#   - RADARR_URL, RADARR_API_KEY: Radarr base URL and API key
#   - CURRENT_YEAR_PROFILE_ID: Quality profile ID for current-year movies
#   - OLDER_MOVIES_PROFILE_ID: Quality profile ID for previous year and older movies
#   - PROCESS_CURRENT_YEAR: Set to "true" to process current year movies, "false" to skip (default: true)
#   - PROCESS_PREVIOUS_YEAR: Set to "true" to process previous year movies, "false" to skip (default: true)
#   - CUSTOM_CURRENT_YEAR: Optional override for current year (leave empty to auto-detect from system date)
#   - CUSTOM_PREVIOUS_YEAR: Optional override for previous year (leave empty to auto-detect)
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Radarr - EDIT FOR YOUR SETUP
RADARR_URL=""           # e.g. http://192.168.1.10:7878 (no trailing slash)
RADARR_API_KEY=""   # Settings → General → API Key

# Quality profile IDs from Radarr (Settings → Profiles). Edit to match your profile IDs.
CURRENT_YEAR_PROFILE_ID="9"   # Profile for current year movies
OLDER_MOVIES_PROFILE_ID="2"   # Profile for previous year and older movies

# 1 = dry run (no API changes), 0 = live
DRY_RUN="0"

# Enable/disable processing of current and previous year (true/false)
PROCESS_CURRENT_YEAR="true"
PROCESS_PREVIOUS_YEAR="true"

# Optional: Override years (leave empty to auto-detect from system date)
CUSTOM_CURRENT_YEAR=""
CUSTOM_PREVIOUS_YEAR=""

# Determine years to use
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

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

main() {
    if ! command -v jq &>/dev/null; then
        log "jq is required but not found."
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        log "Error: curl is required but not installed"
        return 1
    fi
    if [[ -z "$RADARR_URL" || -z "$RADARR_API_KEY" ]]; then
        log "Set RADARR_URL and RADARR_API_KEY."
        return 1
    fi

    # Validate configuration
    if [[ "$PROCESS_CURRENT_YEAR" != "true" && "$PROCESS_CURRENT_YEAR" != "false" ]]; then
        log "Error: PROCESS_CURRENT_YEAR must be 'true' or 'false'"
        return 1
    fi
    if [[ "$PROCESS_PREVIOUS_YEAR" != "true" && "$PROCESS_PREVIOUS_YEAR" != "false" ]]; then
        log "Error: PROCESS_PREVIOUS_YEAR must be 'true' or 'false'"
        return 1
    fi

    if [[ "$PROCESS_CURRENT_YEAR" == "false" && "$PROCESS_PREVIOUS_YEAR" == "false" ]]; then
        log "Both PROCESS_CURRENT_YEAR and PROCESS_PREVIOUS_YEAR are set to false. Nothing to process. Exiting."
        return 0
    fi

    local processing_years=""
    [[ "$PROCESS_CURRENT_YEAR" == "true" ]] && processing_years="$THIS_YEAR"
    [[ "$PROCESS_PREVIOUS_YEAR" == "true" ]] && processing_years="${processing_years:+$processing_years and }$PREV_YEAR"
    log "Radarr Quality Profile Updater – processing movies from year(s): ${processing_years}"

    # Build jq filter based on enabled years
    if [[ "$PROCESS_CURRENT_YEAR" == "true" && "$PROCESS_PREVIOUS_YEAR" == "true" ]]; then
        MOVIES=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/movie" | \
            jq --arg thisyear "$THIS_YEAR" \
               --arg prevyear "$PREV_YEAR" \
               --argjson curprof "$CURRENT_YEAR_PROFILE_ID" \
               '[.[] |
                  select(
                    (.year == ($thisyear|tonumber) and .qualityProfileId != $curprof) or
                    (.year == ($prevyear|tonumber) and .qualityProfileId == $curprof)
                  )
               ]'
        )
    elif [[ "$PROCESS_CURRENT_YEAR" == "true" ]]; then
        MOVIES=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/movie" | \
            jq --arg thisyear "$THIS_YEAR" \
               --argjson curprof "$CURRENT_YEAR_PROFILE_ID" \
               '[.[] |
                  select(.year == ($thisyear|tonumber) and .qualityProfileId != $curprof)
               ]'
        )
    elif [[ "$PROCESS_PREVIOUS_YEAR" == "true" ]]; then
        MOVIES=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/movie" | \
            jq --arg prevyear "$PREV_YEAR" \
               --argjson curprof "$CURRENT_YEAR_PROFILE_ID" \
               '[.[] |
                  select(.year == ($prevyear|tonumber) and .qualityProfileId == $curprof)
               ]'
        )
    else
        MOVIES="[]"
    fi

    TOTAL=$(echo "$MOVIES" | jq 'length')
    log "Found $TOTAL movies that need a quality profile update."

    if [[ "$TOTAL" -eq 0 ]]; then
        log "No movies need updating. Exiting."
        return 0
    fi

    COUNT=0
    CHANGED=0
    REVERTED=0
    TMP_FILE=$(mktemp) || { log "Failed to create temp file"; return 1; }
    echo "$MOVIES" | jq -c '.[]' > "$TMP_FILE"

    while read -r MOVIE; do
        COUNT=$((COUNT + 1))
        MOVIE_ID=$(echo "$MOVIE" | jq '.id')
        MOVIE_TITLE=$(echo "$MOVIE" | jq -r '.title')
        MOVIE_YEAR=$(echo "$MOVIE" | jq '.year')
        PROFILE_ID=$(echo "$MOVIE" | jq '.qualityProfileId')

        if [[ "$PROCESS_CURRENT_YEAR" == "true" && "$MOVIE_YEAR" -eq "$THIS_YEAR" && "$PROFILE_ID" -ne "$CURRENT_YEAR_PROFILE_ID" ]]; then
            if [[ "$DRY_RUN" -eq 0 ]]; then
                FULL_MOVIE=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/movie/$MOVIE_ID")
                UPDATED_MOVIE=$(echo "$FULL_MOVIE" | jq --argjson pid "$CURRENT_YEAR_PROFILE_ID" '.qualityProfileId = $pid')
                curl -s -X PUT -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
                    -d "$UPDATED_MOVIE" "$RADARR_URL/api/v3/movie/$MOVIE_ID" >/dev/null
            fi
            CHANGED=$((CHANGED + 1))
        fi

        if [[ "$PROCESS_PREVIOUS_YEAR" == "true" && "$MOVIE_YEAR" -eq "$PREV_YEAR" && "$PROFILE_ID" -eq "$CURRENT_YEAR_PROFILE_ID" ]]; then
            if [[ "$DRY_RUN" -eq 0 ]]; then
                FULL_MOVIE=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/movie/$MOVIE_ID")
                UPDATED_MOVIE=$(echo "$FULL_MOVIE" | jq --argjson pid "$OLDER_MOVIES_PROFILE_ID" '.qualityProfileId = $pid')
                curl -s -X PUT -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
                    -d "$UPDATED_MOVIE" "$RADARR_URL/api/v3/movie/$MOVIE_ID" >/dev/null
            fi
            REVERTED=$((REVERTED + 1))
        fi
    done < "$TMP_FILE"

    rm -f "$TMP_FILE"
    log "Done. Updated to current year profile: $CHANGED. Reverted to default: $REVERTED. Dry-run: $DRY_RUN"
}

main "$@"
