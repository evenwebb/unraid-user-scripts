#!/bin/bash
#
# server-info-push.sh
# Sends a stylish status summary (space, temps, RAM, UPS, containers) via Unraid dynamix notify
#
# Description:
#   Gathers array/cache/appdata free space, CPU temperatures, RAM usage,
#   uptime, optional UPS status, running VMs, and running Docker containers
#   (Docker section hidden if Docker is not started), then sends a formatted
#   notification via Unraid when enabled.
#
# Usage:
#   ./server-info-push.sh
#
# Configuration:
#   - PUSH_NOTIFICATIONS: 0 = echo only, 1 = Unraid dynamix notify
#   - NOTIFY_SCRIPT: Path to dynamix notify when PUSH_NOTIFICATIONS=1 (empty = print summary only)
#   - ARRAY_MOUNT: Path for df (free space report)
#   - CACHE_MOUNT: Path for df (free space report)
#   - APPDATA_MOUNT: Path for df (free space report)
#   - INCLUDE_UPS: 1 to include UPS status if available (default: 1)
#   - NUT_UPS_NAME: NUT plugin UPS name for upsc (e.g. "ups@localhost", default: auto-detect)
#
# Note: Output goes to stdout; Unraid User Scripts captures it in the GUI.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# 0 = none (echo only), 1 = Unraid notify
PUSH_NOTIFICATIONS="0"

# Unraid dynamix notify when PUSH_NOTIFICATIONS=1 (empty = stdout only)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Mounts to report free space
ARRAY_MOUNT="/mnt/user"
CACHE_MOUNT="/mnt/downloads"
APPDATA_MOUNT="/mnt/appdata"

# Include UPS status if available (1 = yes, 0 = no)
INCLUDE_UPS="1"

# NUT UPS name for upsc (e.g. "ups@localhost"). Empty = auto-detect or use apcaccess
NUT_UPS_NAME=""

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Validate path for safety (reject .., - prefix, newlines — same idea as disk-error-alert / dynamix paths)
is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

pushnotice() {
    local msg="$1"
    if [[ "$PUSH_NOTIFICATIONS" == "1" ]]; then
        [[ -z "$NOTIFY_SCRIPT" ]] && echo "$msg" && return 0
        if ! is_safe_path "$NOTIFY_SCRIPT"; then
            log "Warning: NOTIFY_SCRIPT path invalid."
            echo "$msg"
            return 0
        fi
        if [[ ! -x "$NOTIFY_SCRIPT" ]]; then
            log "Warning: NOTIFY_SCRIPT not executable."
            echo "$msg"
            return 0
        fi
        "$NOTIFY_SCRIPT" -e "Server Info Push" -s "Unraid status" -d "$msg" -i "normal" 2>/dev/null || true
    else
        echo "$msg"
    fi
}

# Format uptime from seconds to human-readable
format_uptime() {
    local secs="${1:-0}"
    local days=$((secs / 86400))
    local hours=$(((secs % 86400) / 3600))
    local mins=$(((secs % 3600) / 60))
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${mins}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

# Get UPS status (apcaccess or NUT upsc)
get_ups_status() {
    if [[ "$INCLUDE_UPS" != "1" ]]; then
        return 0
    fi
    local status=""
    local charge=""
    local runtime=""
    local linev=""

    # Try apcaccess first (APC UPS via apcupsd)
    if command -v apcaccess >/dev/null 2>&1; then
        local apc
        apc=$(apcaccess status 2>/dev/null)
        if [[ -n "$apc" ]]; then
            status=$(echo "$apc" | grep -E '^STATUS' | sed 's/.*: *//' | tr -d ' ')
            charge=$(echo "$apc" | grep -E '^BCHARGE' | awk '{print $2}')
            runtime=$(echo "$apc" | grep -E '^TIMELEFT' | awk '{print $2}')
            linev=$(echo "$apc" | grep -E '^LINEV' | awk '{print $2}')
            [[ -n "$runtime" ]] && runtime="${runtime}min"
        fi
    fi

    # Try NUT upsc if apcaccess didn't work
    if [[ -z "$status" ]] && command -v upsc >/dev/null 2>&1; then
        local ups_name="$NUT_UPS_NAME"
        if [[ -z "$ups_name" ]]; then
            ups_name=$(upsc -l 2>/dev/null | head -n1)
        fi
        if [[ -n "$ups_name" ]]; then
            status=$(upsc "$ups_name" ups.status 2>/dev/null || true)
            charge=$(upsc "$ups_name" battery.charge 2>/dev/null || true)
            runtime=$(upsc "$ups_name" battery.runtime 2>/dev/null || true)
            linev=$(upsc "$ups_name" input.voltage 2>/dev/null || true)
        fi
    fi

    if [[ -z "$status" ]]; then
        return 0
    fi

    # Build UPS line (format runtime for NUT: seconds -> min)
    local runtime_fmt="$runtime"
    if [[ -n "$runtime" ]] && [[ "$runtime" =~ ^[0-9]+$ ]]; then
        local mins=$((runtime / 60))
        runtime_fmt="${mins}min"
    fi
    local line="  Status: ${status:-N/A}"
    [[ -n "$charge" ]] && line="$line  |  Charge: ${charge}%"
    [[ -n "$runtime_fmt" ]] && line="$line  |  Runtime: ${runtime_fmt}"
    [[ -n "$linev" ]] && line="$line  |  Input: ${linev}V"
    echo "$line"
}

main() {
    if [[ "$PUSH_NOTIFICATIONS" != "0" && "$PUSH_NOTIFICATIONS" != "1" ]]; then
        log_err "PUSH_NOTIFICATIONS must be 0 or 1."
        return 1
    fi

    for m in ARRAY_MOUNT CACHE_MOUNT APPDATA_MOUNT; do
        if ! is_safe_path "${!m}"; then
            log_err "Invalid path for $m."
            return 1
        fi
    done
    if [[ "$PUSH_NOTIFICATIONS" == "1" ]] && [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi

    log "Gathering server status..."

    # Storage
    local hdspacefree=$(df -h "$ARRAY_MOUNT" 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")
    local cachespacefree=$(df -h "$CACHE_MOUNT" 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")
    local appdataspacefree=$(df -h "$APPDATA_MOUNT" 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")

    # Temperatures
    local temp="N/A"
    if command -v sensors >/dev/null 2>&1; then
        temp=$(timeout 5 sensors 2>/dev/null | grep -E '°[CF]' | head -n 3 | sed 's/^[[:space:]]*//' | paste -sd ', ' - || echo "N/A")
        [[ -z "$temp" ]] && temp="N/A"
    fi

    # RAM
    local ram_used ram_total ram_pct
    ram_used=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}' || echo "N/A")
    ram_total=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "N/A")
    ram_pct=$(free 2>/dev/null | awk '/^Mem:/ {if ($2>0) printf "%.0f", $3/$2*100}' 2>/dev/null || echo "")
    local ram_line="  ${ram_used:-N/A} / ${ram_total:-N/A}"
    [[ -n "$ram_pct" ]] && ram_line="$ram_line  (${ram_pct}% used)"

    # Uptime & load
    local uptime_secs load
    uptime_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
    load=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || echo "N/A")
    local uptime_str
    uptime_str=$(format_uptime "$uptime_secs")

    # VMs (virsh/libvirt)
    local vmslist="none"
    if command -v virsh >/dev/null 2>&1; then
        vmslist=$(virsh list --state-running --name 2>/dev/null | paste -sd ', ' - || echo "none")
        [[ -z "$vmslist" ]] && vmslist="none"
    fi

    # Docker containers (only if Docker daemon is running)
    local docsrunning=""
    local docker_running=0
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        docker_running=1
        docsrunning=$(docker ps --format '{{.Names}}' 2>/dev/null | paste -sd ', ' - || echo "none")
        [[ -z "$docsrunning" ]] && docsrunning="none"
    fi

    # UPS
    local ups_line
    ups_line=$(get_ups_status)

    # Build styled message
    local msg
    msg="🖥️  Unraid Server Status
━━━━━━━━━━━━━━━━━━━━━━

📁  Storage
  Array:      $hdspacefree free
  Downloads:  $cachespacefree free
  AppData:    $appdataspacefree free

🌡️  Temperatures
  $temp

💾  Memory
$ram_line

⏱️  Uptime  |  Load
  $uptime_str  |  $load"

    if [[ -n "$ups_line" ]]; then
        msg="$msg

🔌  UPS
$ups_line"
    fi

    if [[ -n "$vmslist" && "$vmslist" != "none" ]]; then
        msg="$msg

🖴  VMs
  $vmslist"
    fi

    if [[ $docker_running -eq 1 ]]; then
        msg="$msg

🐳  Containers
  $docsrunning"
    fi

    pushnotice "$msg"

    log "Done."
}

main "$@"
