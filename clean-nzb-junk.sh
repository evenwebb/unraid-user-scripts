#!/bin/bash
#
# clean-nzb-junk.sh
# Removes NZB download junk files and empty directories
#
# Description:
#   Cleans up common junk files left by NZB downloaders (nfo, par2, samples, etc.)
#   and removes empty directories after cleanup.
#
# Usage:
#   ./clean-nzb-junk.sh              # Run in production mode (deletes files)
#   DEBUG=1 ./clean-nzb-junk.sh      # Dry-run mode (shows what would be deleted)
#
# Configuration:
#   - Edit FOLDERS array below to set your download directories
#   - Edit JUNK_EXTENSIONS to customize file patterns to remove
#   - Set DEBUG=1 in the script for permanent dry-run mode
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

# Only exit on undefined variables, not on errors (more forgiving)
set -u

# DEBUG MODE: set to 1 for dry-run (no actual deletions), 0 for production
DEBUG="0"

# Directories to clean - EDIT THESE FOR YOUR SETUP
FOLDERS=(
    "/mnt/user/downloads/complete/tv"
    "/mnt/user/downloads/complete/movies"
)

# File extensions to remove (junk files) - EDIT TO CUSTOMIZE
JUNK_EXTENSIONS=(
    "*.nfo" "*.NFO"          # NFO info files
    "*.sfv" "*.srs" "*.srr"  # Verification files
    "*.nzb" "*.url"          # Download files
    "*.html" "*.htm"         # Web files
    "*.log" "*.txt"          # Log/text files (BE CAREFUL - may remove wanted txt files)
    "*.par2" "*.vol*.par2"   # Parity files
    "*.md5" "*.lnk"          # Checksums and shortcuts
    "*.m3u" "*.m3u8"         # Playlist files
    "*.jpg" "*.jpeg" "*.png" "*.gif" "*.bmp"  # Image files
    "*.exe" "*.com" "*.bat" "*.cmd" "*.scr" "*.dll"  # Windows executables
    "*.rar" "*.r[0-9]" "*.r[0-9][0-9]"  # RAR archives
    "*.zip" "*.7z"           # Other archives
    ".DS_Store" "Thumbs.db"  # OS junk files
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
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

    # Get all files, then filter in bash (single find per directory)
    while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        local matched=0

        ((processed++)) || true

        # Check if file matches any junk pattern
        for pattern in "${JUNK_EXTENSIONS[@]}"; do
            # Convert glob pattern to bash pattern matching
            pattern="${pattern#\*}"  # Remove leading *
            # Handle RAR split files: .r[0-9] and .r[0-9][0-9] need regex matching
            if [[ "$pattern" == ".r[0-9]" ]] || [[ "$pattern" == ".r[0-9][0-9]" ]]; then
                # Use regex to match .r followed by 1+ digits (handles .r0 through .r999+)
                if [[ "$basename" =~ \.r[0-9]+$ ]]; then
                    matched=1
                    break
                fi
            elif [[ "$basename" == *"$pattern" ]] || [[ "$basename" == "$pattern" ]]; then
                matched=1
                break
            fi
        done

        if [[ $matched -eq 1 ]]; then
            if [[ "$DEBUG" == "1" ]]; then
                # Only log in debug if verbose logging is needed - comment out for less spam
                : # log "  Would delete: $file"
            else
                rm -f "$file"
            fi
            ((count++)) || true
        fi

        # Progress indicator every 100 files
        if (( processed % 100 == 0 )); then
            log "  Processed $processed files, found $count junk files so far..."
        fi
    done < <(find "$dir" -xdev -type f -print0 2>&1 || true)

    log "Scanned $processed files, found $count junk file(s) to delete"
}

# Delete sample files (filename ends with "sample" or "sample[0-9]+" before extension)
delete_sample_files() {
    local dir="$1"
    local count=0

    if [[ ! -d "$dir" ]]; then
        return 0
    fi

    log "Scanning for sample files in: $dir"

    # Find all files with "sample" in the name
    while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        local name_no_ext="${basename%.*}"
        local name_lower="${name_no_ext,,}"

        # Check if filename ends with "sample" or "sample" followed by digits
        if [[ "$name_lower" =~ sample[0-9]*$ ]]; then
            if [[ "$DEBUG" == "1" ]]; then
                : # Quiet mode
            else
                rm -f "$file"
            fi
            ((count++)) || true
        fi
    done < <(find "$dir" -xdev -type f -iname "*sample*" -print0 2>&1 || true)

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
        if [[ "$DEBUG" == "1" ]]; then
            : # Quiet mode
        else
            rm -rf "$sdir"
        fi
        ((count++)) || true
    done < <(find "$dir" -xdev -type d -iname "sample" -print0 2>&1 || true)

    log "Found $count sample director(ies)"
}

# Delete empty directories (run multiple times until no more found)
delete_empty_dirs() {
    local dir="$1"
    local total=0
    local pass=0

    if [[ ! -d "$dir" ]]; then
        return 0
    fi

    log "Cleaning empty directories in: $dir"

    # In DEBUG mode, just count once and exit
    if [[ "$DEBUG" == "1" ]]; then
        while IFS= read -r -d '' empty_dir; do
            ((total++)) || true
        done < <(find "$dir" -xdev -type d -empty -print0 2>&1 || true)
        log "Found $total empty director(ies) (would delete in non-debug mode)"
        return 0
    fi

    # In production mode, keep removing until no more found
    while true; do
        local count=0
        ((pass++)) || true

        while IFS= read -r -d '' empty_dir; do
            rmdir "$empty_dir" 2>/dev/null && ((count++)) || true
        done < <(find "$dir" -xdev -type d -empty -print0 2>&1 || true)

        # Stop when no more empty dirs found
        [[ $count -eq 0 ]] && break

        ((total += count)) || true
        [[ $count -gt 0 ]] && log "  Pass $pass: removed $count empty director(ies)"
    done

    log "Removed $total empty director(ies) total"
}

# Main execution
main() {
    local start_time=$(date +%s)

    if [[ "$DEBUG" == "1" ]]; then
        log "Starting cleanup (DRY RUN - no deletions)"
    else
        log "Starting cleanup"
    fi

    for folder in "${FOLDERS[@]}"; do
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
