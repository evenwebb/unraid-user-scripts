#!/bin/bash
#
# record-disk-assignments.sh
# Records current Unraid disk assignments to a text file on the flash drive
#
# Description:
#   Reads /var/local/emhttp/disks.ini and writes a human-readable summary
#   to /boot/config/DISK_ASSIGNMENTS.txt. Useful for backup or documentation
#   (if not using CA Backup plugin which does this automatically).
#
# Usage:
#   ./record-disk-assignments.sh
#
# Configuration:
#   - DISKS_INI: Path to Unraid disks.ini (default /var/local/emhttp/disks.ini)
#   - OUTPUT_FILE: Output path (default /boot/config/DISK_ASSIGNMENTS.txt)
#
# Note: Output goes to stdout; Unraid User Scripts captures it in the GUI.
##   - JSON_OUTPUT: 1 = also write JSON output file (OUTPUT_FILE.json)

# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Unraid disks.ini path
DISKS_INI="/var/local/emhttp/disks.ini"

# Output file path
OUTPUT_FILE="/boot/config/DISK_ASSIGNMENTS.txt"

# 1 = also write a JSON version alongside the text file (OUTPUT_FILE.json)
JSON_OUTPUT="0"

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

flush_disk() {
    [[ -z "$d_name" && -z "$d_id" ]] && return 0
    echo "Disk: ${d_name:-}  Device: ${d_id:-}  Status: ${d_status:-}" >> "$OUTPUT_FILE"
}

main() {
    if [[ -z "$DISKS_INI" ]] || [[ "$DISKS_INI" == *".."* || "$DISKS_INI" == "-"* ]]; then
        log_err "DISKS_INI invalid."
        return 1
    fi
    if [[ -z "$OUTPUT_FILE" ]] || [[ "$OUTPUT_FILE" == *".."* || "$OUTPUT_FILE" == "-"* ]]; then
        log_err "OUTPUT_FILE invalid."
        return 1
    fi
    if [[ ! -r "$DISKS_INI" ]]; then
        log_err "Cannot read $DISKS_INI"
        return 1
    fi

    mkdir -p "$(dirname "$OUTPUT_FILE")" 2>/dev/null || true
    echo "Disk Assignments as of $(date -R)" > "$OUTPUT_FILE" || { log_err "Cannot write to $OUTPUT_FILE"; return 1; }

    d_name=""
    d_id=""
    d_status=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        if [[ "$line" == \[*\] ]]; then
            flush_disk
            d_name=""
            d_id=""
            d_status=""
        elif [[ "$line" == *=* ]]; then
            key="${line%%=*}"
            key="${key%"${key##*[![:space:]]}"}"
            val="${line#*=}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            case "$key" in
                name)   d_name="$val" ;;
                id)     d_id="$val" ;;
                status) d_status="$val" ;;
            esac
        fi
    done < "$DISKS_INI"

    flush_disk

    log "Disk assignments saved to $OUTPUT_FILE"

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        local json_file="${OUTPUT_FILE}.json"
        {
            echo "{"
            echo "  "date": "$(date -Iseconds)","
            echo "  "disks": ["
            local first=1 dname did dstatus
            while IFS= read -r line; do
                [[ -z "$line" || "$line" == "Disk Assignments as of"* ]] && continue
                if [[ "$line" =~ ^Disk:[[:space:]]+(.*)[[:space:]]+Device:[[:space:]]+(.*)[[:space:]]+Status:[[:space:]]+(.*) ]]; then
                    dname="${BASH_REMATCH[1]}"
                    did="${BASH_REMATCH[2]}"
                    dstatus="${BASH_REMATCH[3]}"
                    [[ $first -eq 0 ]] && echo ","
                    printf '    {"name": "%s", "device": "%s", "status": "%s"}' "$dname" "$did" "$dstatus"
                    first=0
                fi
            done < "$OUTPUT_FILE"
            echo ""
            echo "  ]"
            echo "}"
        } > "$json_file" || log_err "Failed to write JSON output: $json_file"
        log "JSON disk assignments saved to $json_file"
    fi
}

main "$@"
