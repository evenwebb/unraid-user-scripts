#!/bin/bash
#
# clean-torrent-junk.sh
# Removes torrent download junk files and empty directories
#
# Description:
#   Cleans up common junk files left by torrent downloads (nfo, par2, samples,
#   RAR splits, etc.) and removes empty directories after cleanup.
#
# Usage:
#   ./clean-torrent-junk.sh              # Run in production mode (deletes files)
#   Set DRY_RUN=1 in the script for dry-run mode (no deletions)
#
# Configuration (edit script variables below):
#   - FOLDERS: Directories to clean
#   - JUNK_EXTENSIONS: File patterns to remove
#   - DRY_RUN: 1 for dry-run (no deletions), 0 for production
#
# Output goes to stdout; Unraid User Scripts captures it in the GUI.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# 1 = dry-run (no deletions), 0 = production
DRY_RUN="0"

# Directories to clean - EDIT THESE FOR YOUR SETUP
FOLDERS=(
    "/mnt/user/downloads/complete/torrents"
    "/mnt/user/downloads/complete/movies"
    "/mnt/user/downloads/complete/tv"
)

# File extensions to remove (junk files) - EDIT TO CUSTOMIZE (case insensitive)
JUNK_EXTENSIONS=(
    "*.nfo"                  # NFO info files
    "*.sfv" "*.srs" "*.srr"  # Verification files
    "*.torrent" "*.url"      # Torrent/magnet files
    "*.html" "*.htm"         # Web files
    "*.log" "*.txt"          # Log/text files (BE CAREFUL - may remove wanted txt files)
    "*.par2" "*.vol*.par2"   # Parity files
    "*.md5" "*.lnk"          # Checksums and shortcuts
    "*.m3u" "*.m3u8"         # Playlist files
    "*.jpg" "*.jpeg" "*.png" "*.gif" "*.bmp"  # Image files
    "*.exe" "*.com" "*.bat" "*.cmd" "*.scr" "*.dll"  # Windows executables
    "*.rar" "*.r[0-9]" "*.r[0-9][0-9]"  # RAR archives
    "*.zip" "*.7z"           # Other archives
    ".DS_Store" "Thumbs.db"   # OS junk files
    "*.!ut" "*.!utpart"      # uTorrent incomplete
    "*.bc!"                  # BitComet incomplete
    "*.!qb"                  # qBittorrent incomplete
    "*.!sync" "*.!bt"        # Resilio Sync / BitTorrent
    "*.pad"                  # Padding files (often 0-byte)
    "*.tmp" "*.temp"         # Temp files
    "*.crc" "*.crc32"        # Checksum files
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Validate path for safety (reject .. and - prefix)
is_safe_path() {
    local p="$1"
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    return 0
}

# Delete junk files by extension
delete_junk_files() {
    local dir="$1"
    local count=0
    local processed=0

    if [[ ! -d "$dir" ]]; then
        log "Skipping $dir (not found)"
        return 0
    fi

    log "Scanning for junk files in: $dir"

    while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        local matched=0

        ((processed++)) || true

        local basename_lower="${basename,,}"
        for pattern in "${JUNK_EXTENSIONS[@]}"; do
            pattern="${pattern#\*}"
            local pattern_lower="${pattern,,}"
            if [[ "$pattern_lower" == ".r[0-9]" ]] || [[ "$pattern_lower" == ".r[0-9][0-9]" ]]; then
                if [[ "$basename_lower" =~ \.r[0-9]+$ ]]; then
                    matched=1
                    break
                fi
            elif [[ "$basename_lower" == *"$pattern_lower" ]] || [[ "$basename_lower" == "$pattern_lower" ]]; then
                matched=1
                break
            fi
        done

        if [[ $matched -eq 1 ]]; then
            if [[ "$DRY_RUN" != "1" ]]; then
                rm -f "$file"
            fi
            ((count++)) || true
        fi

        if (( processed % 100 == 0 )); then
            log "  Processed $processed files, found $count junk files so far..."
        fi
    done < <(find "$dir" -xdev -type f -print0 2>/dev/null || true)

    log "Scanned $processed files, found $count junk file(s) to delete"
}

# Delete sample files
delete_sample_files() {
    local dir="$1"
    local count=0

    if [[ ! -d "$dir" ]]; then
        return 0
    fi

    log "Scanning for sample files in: $dir"

    while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        local name_no_ext="${basename%.*}"
        local name_lower="${name_no_ext,,}"

        if [[ "$name_lower" =~ sample[0-9]*$ ]]; then
            if [[ "$DRY_RUN" != "1" ]]; then
                rm -f "$file"
            fi
            ((count++)) || true
        fi
    done < <(find "$dir" -xdev -type f -iname "*sample*" -print0 2>/dev/null || true)

    log "Found $count sample file(s)"
}

# Delete sample directories
delete_sample_dirs() {
    local dir="$1"
    local count=0

    if [[ ! -d "$dir" ]]; then
        return 0
    fi

    log "Scanning for sample directories in: $dir"

    while IFS= read -r -d '' sdir; do
        if [[ "$DRY_RUN" != "1" ]]; then
            rm -rf "$sdir"
        fi
        ((count++)) || true
    done < <(find "$dir" -xdev -type d -iname "sample" -print0 2>/dev/null || true)

    log "Found $count sample director(ies)"
}

# Delete empty directories
delete_empty_dirs() {
    local dir="$1"
    local total=0
    local pass=0

    if [[ ! -d "$dir" ]]; then
        return 0
    fi

    log "Cleaning empty directories in: $dir"

    if [[ "$DRY_RUN" == "1" ]]; then
        while IFS= read -r -d '' empty_dir; do
            ((total++)) || true
        done < <(find "$dir" -xdev -type d -empty -print0 2>/dev/null || true)
        log "Found $total empty director(ies) (would delete in non-debug mode)"
        return 0
    fi

    while true; do
        local count=0
        ((pass++)) || true

        while IFS= read -r -d '' empty_dir; do
            rmdir "$empty_dir" 2>/dev/null && ((count++)) || true
        done < <(find "$dir" -xdev -type d -empty -print0 2>/dev/null || true)

        [[ $count -eq 0 ]] && break

        ((total += count)) || true
        [[ $count -gt 0 ]] && log "  Pass $pass: removed $count empty director(ies)"
    done

    log "Removed $total empty director(ies) total"
}

main() {
    local start_time=$(date +%s)

    if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
        log_err "DRY_RUN must be 0 or 1."
        return 1
    fi
    [[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no files or directories will be deleted"
    if [[ ${#FOLDERS[@]} -eq 0 ]]; then
        log_err "FOLDERS is empty. Add at least one directory to clean."
        return 1
    fi

    for folder in "${FOLDERS[@]}"; do
        if ! is_safe_path "$folder"; then
            log_err "Skipping unsafe path: $folder"
            continue
        fi
        if [[ -z "$folder" ]]; then
            log_err "Skipping empty folder entry."
            continue
        fi
        log "Processing: $folder"
        delete_junk_files "$folder"
        delete_sample_files "$folder"
        delete_sample_dirs "$folder"
        delete_empty_dirs "$folder"
        log "Completed: $folder"
        echo ""
    done

    local duration=$(($(date +%s) - start_time))
    log "Cleanup completed in ${duration}s"
}

main "$@"
