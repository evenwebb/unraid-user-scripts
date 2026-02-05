#!/bin/bash
#
# server-info-push.sh
# Sends a status summary (space, temps, running containers) via Pushover or Pushbullet
#
# Description:
#   Gathers array/cache/appdata free space, CPU temperatures, and optionally
#   running Docker containers, then sends one notification to your phone.
#
# Usage:
#   ./server-info-push.sh
#
# Configuration:
#   - PUSH_NOTIFICATIONS: 0 = echo only, 1 = Pushover, 2 = Pushbullet
#   - For Pushover: set PUSHOVER_APP_TOKEN and PUSHOVER_USER_KEY
#   - For Pushbullet: set PUSHBULLET_API_KEY
#   - Edit MOUNTS for df paths (array, cache, appdata) to match your setup
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# 0 = none (echo only), 1 = Pushover, 2 = Pushbullet
PUSH_NOTIFICATIONS="0"

# Pushover (when PUSH_NOTIFICATIONS=1)
PUSHOVER_APP_TOKEN=""
PUSHOVER_USER_KEY=""

# Pushbullet (when PUSH_NOTIFICATIONS=2)
PUSHBULLET_API_KEY=""

# Mounts to report free space - EDIT FOR YOUR SETUP
ARRAY_MOUNT="/mnt/user"
CACHE_MOUNT="/mnt/downloads"
APPDATA_MOUNT="/mnt/appdata"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

pushnotice() {
    local msg="$1"
    if [[ "$PUSH_NOTIFICATIONS" == "1" ]]; then
        # Validate Pushover configuration (both or neither)
        if [[ -n "$PUSHOVER_APP_TOKEN" ]] && [[ -z "$PUSHOVER_USER_KEY" ]]; then
            log "Warning: PUSHOVER_APP_TOKEN is set but PUSHOVER_USER_KEY is missing. Notifications disabled."
            echo "$msg"
            return 0
        elif [[ -z "$PUSHOVER_APP_TOKEN" ]] && [[ -n "$PUSHOVER_USER_KEY" ]]; then
            log "Warning: PUSHOVER_USER_KEY is set but PUSHOVER_APP_TOKEN is missing. Notifications disabled."
            echo "$msg"
            return 0
        fi
        [[ -z "$PUSHOVER_APP_TOKEN" || -z "$PUSHOVER_USER_KEY" ]] && echo "$msg" && return 0
        if ! command -v curl >/dev/null 2>&1; then
            log "Warning: curl not found, cannot send Pushover notification"
            echo "$msg"
            return 0
        fi
        curl -s --form-string "token=$PUSHOVER_APP_TOKEN" --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "message=$msg" https://api.pushover.net/1/messages.json >/dev/null 2>&1 || true
    elif [[ "$PUSH_NOTIFICATIONS" == "2" ]]; then
        [[ -z "$PUSHBULLET_API_KEY" ]] && echo "$msg" && return 0
        if ! command -v curl >/dev/null 2>&1; then
            log "Warning: curl not found, cannot send Pushbullet notification"
            echo "$msg"
            return 0
        fi
        curl -s -u "$PUSHBULLET_API_KEY": -d type=note -d title="Unraid status" -d body="$msg" \
            https://api.pushbullet.com/v2/pushes >/dev/null 2>&1 || true
    else
        echo "$msg"
    fi
}

main() {
    # Get running Docker containers (container names, not images)
    if command -v docker >/dev/null 2>&1; then
        docsrunning=$(docker ps --format '{{.Names}}' 2>/dev/null | paste -sd ',' - || echo "N/A")
    else
        docsrunning="N/A (docker not available)"
    fi
    
    # Get temperature (if sensors available)
    if command -v sensors >/dev/null 2>&1; then
        # Extract only lines with actual temperature readings (containing °C or °F)
        # Format: "Core 0: +45.0°C" or similar
        temp=$(sensors 2>/dev/null | grep -E '°[CF]' | head -n 3 | sed 's/^[[:space:]]*//' | paste -sd ', ' - || echo "N/A")
        [[ -z "$temp" ]] && temp="N/A (no temperature data)"
    else
        temp="N/A (sensors not available)"
    fi
    hdspacefree=$(df -h "$ARRAY_MOUNT" 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")
    cachespacefree=$(df -h "$CACHE_MOUNT" 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")
    appdataspacefree=$(df -h "$APPDATA_MOUNT" 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")

    pushnotice "Array Space Free: $hdspacefree
Downloads Space Free: $cachespacefree
AppData Space Free: $appdataspacefree

Temperatures:
$temp

Running containers:
$docsrunning"
}

main "$@"
