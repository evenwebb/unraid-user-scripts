#!/bin/bash
#
# flash-backup.sh
# Creates a compressed backup of the Unraid boot flash drive to the array
#
# Description:
#   Backs up /boot (the Unraid USB flash drive) to a configurable destination
#   on the array. The flash drive contains your Unraid license (.key file),
#   disk assignments (super.dat), Docker templates, VM XML, and all system
#   configuration. If the flash drive fails, this backup is essential for
#   recovery.
#
#   - Creates a compressed tar archive of /boot
#   - Rotates old backups (keeps last KEEP_COUNT copies)
#   - Optionally verifies backup integrity after creation
#   - Optionally excludes large/transient paths (logs, previous backups)
#   - Reports backup size and duration via notification
#
# Usage:
#   ./flash-backup.sh
#
# Configuration (edit script variables below):
#   - BACKUP_DEST: Directory for backup archives (must be on array/cache)
#   - KEEP_COUNT: Number of backups to retain (0 = unlimited)
#   - COMPRESSION: gzip, bzip2, xz, or none
#   - VERIFY_BACKUP: 1 = verify archive integrity after creation, 0 = skip
#   - EXCLUDE_LOGS: 1 = exclude /boot/logs (can be large), 0 = include
#   - EXCLUDE_PREVIOUS_BACKUPS: 1 = exclude existing backups from archive, 0 = skip
#   - NOTIFY_SCRIPT: Unraid dynamix notify script path
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#   - MAX_BACKUP_SIZE_MB: Warn if backup exceeds this size (0 = no limit)
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Destination directory for backups (must be on array or cache, not /boot itself)
BACKUP_DEST="/mnt/user/backups/flash"

# Number of backup archives to retain (0 = keep all, recommended 4-8)
KEEP_COUNT="6"

# Compression type: gzip (fast, good balance), bzip2 (smaller, slower), xz (smallest, very slow), none
COMPRESSION="gzip"

# 1 = verify archive integrity after creation (adds ~30s-2min for large flash drives)
VERIFY_BACKUP="1"

# 1 = exclude /boot/logs (can grow large from syslog mirroring)
EXCLUDE_LOGS="1"

# 1 = exclude files matching previous backup patterns from the archive
EXCLUDE_PREVIOUS_BACKUPS="1"

# Unraid dynamix notify script
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Warn if backup archive exceeds this size in MB (0 = no limit)
MAX_BACKUP_SIZE_MB="0"

###############################################################################

# Validate paths
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid." >&2
    exit 1
fi
if [[ -n "$NOTIFY_SCRIPT" ]] && [[ "$NOTIFY_SCRIPT" == *".."* || "$NOTIFY_SCRIPT" == "-"* ]]; then
    echo "Error: NOTIFY_SCRIPT path invalid." >&2
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
    echo "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    return 0
}

send_notify() {
    local event="$1" subject="$2" desc="$3" importance="${4:-normal}"
    if [[ -n "$NOTIFY_SCRIPT" ]] && is_safe_path "$NOTIFY_SCRIPT" && [[ -x "$NOTIFY_SCRIPT" ]]; then
        "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$desc" -i "$importance" 2>/dev/null || true
    fi
}

get_compression_flag() {
    case "$COMPRESSION" in
        gzip)  echo "z" ;;
        bzip2) echo "j" ;;
        xz)    echo "J" ;;
        *)     echo "" ;;
    esac
}

get_compression_ext() {
    case "$COMPRESSION" in
        gzip)  echo ".gz" ;;
        bzip2) echo ".bz2" ;;
        xz)    echo ".xz" ;;
        *)     echo "" ;;
    esac
}

main() {
    if ! is_safe_path "$BACKUP_DEST"; then
        log_err "BACKUP_DEST path invalid."
        return 1
    fi
    if [[ "$KEEP_COUNT" != "0" ]] && [[ ! "$KEEP_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        log_err "KEEP_COUNT must be 0 or a positive integer."
        return 1
    fi
    case "$COMPRESSION" in
        gzip|bzip2|xz|none) ;;
        *) log_err "COMPRESSION must be gzip, bzip2, xz, or none."; return 1 ;;
    esac

    if [[ ! -d "/boot" ]]; then
        log_err "/boot not mounted (flash drive not found)."
        return 1
    fi

    # Require destination to NOT be on /boot itself
    local dest_real
    dest_real=$(readlink -f "$BACKUP_DEST" 2>/dev/null || echo "$BACKUP_DEST")
    if [[ "$dest_real" == "/boot" || "$dest_real" == "/boot/"* ]]; then
        log_err "BACKUP_DEST must not be on the flash drive itself."
        return 1
    fi

    # Check for required tools
    for cmd in tar; do
        if ! command -v "$cmd" &>/dev/null; then
            log_err "$cmd is required but not found."
            return 1
        fi
    done

    if [[ "$VERIFY_BACKUP" == "1" ]]; then
        case "$COMPRESSION" in
            gzip)  command -v gzip &>/dev/null || { log_err "gzip required for verification"; return 1; } ;;
            bzip2) command -v bzip2 &>/dev/null || { log_err "bzip2 required for verification"; return 1; } ;;
            xz)    command -v xz &>/dev/null || { log_err "xz required for verification"; return 1; } ;;
        esac
    fi

    mkdir -p "$BACKUP_DEST" 2>/dev/null || { log_err "Cannot create backup destination: $BACKUP_DEST"; return 1; }

    local timestamp comp_flag comp_ext backup_name backup_path
    timestamp=$(date '+%Y%m%d-%H%M%S')
    comp_flag=$(get_compression_flag)
    comp_ext=$(get_compression_ext)
    backup_name="unraid-flash-backup-${timestamp}.tar${comp_ext}"
    backup_path="${BACKUP_DEST}/${backup_name}"

    log "Starting flash backup to: $backup_path"

    # Build tar exclusions
    local exclude_args=()
    if [[ "$EXCLUDE_LOGS" == "1" ]]; then
        exclude_args+=(--exclude="/boot/logs")
    fi
    if [[ "$EXCLUDE_PREVIOUS_BACKUPS" == "1" ]]; then
        # Exclude the backup destination from the archive if it's under /mnt
        [[ "$BACKUP_DEST" == "/mnt/"* ]] && exclude_args+=(--exclude="${BACKUP_DEST}")
    fi
    # Always exclude transient/runtime files
    exclude_args+=(--exclude="/boot/EFI")

    local start_time size_before size_after duration exit_code
    start_time=$(date +%s)

    if [[ -n "$comp_flag" ]]; then
        tar "${exclude_args[@]}" -c${comp_flag}f "$backup_path" -C / boot 2>/dev/null
        exit_code=$?
    else
        tar "${exclude_args[@]}" -cf "$backup_path" -C / boot 2>/dev/null
        exit_code=$?
    fi

    duration=$(($(date +%s) - start_time))

    if [[ $exit_code -ne 0 ]]; then
        log_err "Backup failed (tar exit code $exit_code)."
        send_notify "Flash Backup" "Flash backup failed" \
            "tar exited with code $exit_code after ${duration}s. Check $LOG_FILE for details." \
            "alert"
        return 1
    fi

    # Check backup size
    local backup_size_kb backup_size_mb
    backup_size_kb=$(du -k "$backup_path" 2>/dev/null | awk '{print $1}' || echo 0)
    backup_size_mb=$((backup_size_kb / 1024))
    log "Backup created: ${backup_size_mb}MB in ${duration}s"

    if [[ "$MAX_BACKUP_SIZE_MB" -gt 0 ]] && [[ "$backup_size_mb" -gt "$MAX_BACKUP_SIZE_MB" ]]; then
        log "WARNING: Backup size (${backup_size_mb}MB) exceeds MAX_BACKUP_SIZE_MB (${MAX_BACKUP_SIZE_MB}MB)."
    fi

    # Verify integrity
    if [[ "$VERIFY_BACKUP" == "1" ]]; then
        log "Verifying backup integrity..."
        if [[ "$COMPRESSION" == "gzip" ]]; then
            gzip -t "$backup_path" 2>/dev/null
        elif [[ "$COMPRESSION" == "bzip2" ]]; then
            bzip2 -t "$backup_path" 2>/dev/null
        elif [[ "$COMPRESSION" == "xz" ]]; then
            xz -t "$backup_path" 2>/dev/null
        else
            tar -tf "$backup_path" >/dev/null 2>&1
        fi
        if [[ $? -ne 0 ]]; then
            log_err "Backup verification FAILED for $backup_path"
            send_notify "Flash Backup" "Flash backup verification failed" \
                "Backup archive $backup_name failed integrity check. The backup may be corrupt." \
                "alert"
            return 1
        fi
        log "Verification passed."
    fi

    # Rotate old backups
    if [[ "$KEEP_COUNT" -gt 0 ]]; then
        log "Rotating backups (keeping last $KEEP_COUNT)..."
        local old_backups removed
        old_backups=$(find "$BACKUP_DEST" -maxdepth 1 -type f -name "unraid-flash-backup-*.tar*" 2>/dev/null | sort)
        local total
        total=$(echo "$old_backups" | grep -c . 2>/dev/null || echo 0)
        if [[ "$total" -gt "$KEEP_COUNT" ]]; then
            local to_remove=$((total - KEEP_COUNT))
            echo "$old_backups" | head -n "$to_remove" | while IFS= read -r old; do
                [[ -z "$old" ]] && continue
                rm -f "$old" && log "  Removed: $(basename "$old")"
            done
        fi
    fi

    local msg="Flash backup completed: ${backup_size_mb}MB in ${duration}s → ${backup_name}"
    log "$msg"
    send_notify "Flash Backup" "Flash backup completed" \
        "$msg. Stored in $BACKUP_DEST (keeping last $KEEP_COUNT backups)." \
        "normal"

    return 0
}

main "$@"
