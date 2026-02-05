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
#   OUTPUT_FILE=/path/to/file.txt ./record-disk-assignments.sh
#
# Configuration:
#   - OUTPUT_FILE: Output path (default /boot/config/DISK_ASSIGNMENTS.txt)
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

DISKS_INI="/var/local/emhttp/disks.ini"
OUTPUT_FILE="/boot/config/DISK_ASSIGNMENTS.txt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

flush_disk() {
    [[ -z "$d_name" && -z "$d_id" && -z "$d_status" ]] && return 0
    echo "Disk: ${d_name:-}  Device: ${d_id:-}  Status: ${d_status:-}" >> "$OUTPUT_FILE"
}

main() {
    if [[ ! -r "$DISKS_INI" ]]; then
        log "Cannot read $DISKS_INI"
        return 1
    fi

    echo "Disk Assignments as of $(date -R)" > "$OUTPUT_FILE"

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

    log "Disk assignments have been saved to $OUTPUT_FILE"
}

main "$@"
