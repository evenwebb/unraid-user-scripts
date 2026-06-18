#!/bin/bash
#
# remove-os-metadata.sh
# Remove macOS and Windows metadata files from media paths.
#
# Description:
#   Deletes .DS_Store, Thumbs.db, resource forks, etc. Defaults to dry run.
#
# Usage:
#   ./remove-os-metadata.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only (default), 0 = delete files
#
# Configuration (edit script variables below):
#   - SEARCH_PATHS: directories to scan
#   - MAX_DEPTH: find depth limit
#   - DELETE_MACOS_METADATA / DELETE_WINDOWS_METADATA / INCLUDE_RESOURCE_FORKS
#   - DRY_RUN: 1 = preview only (default), 0 = delete files
#   - LOG_FILE: optional log file
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

# Directories to search
SEARCH_PATHS=(
    "/mnt/user"
    "/mnt/appdata"
    "/mnt/downloads"
)

# Maximum find depth (9999 = effectively unlimited; lower to limit scan depth)
MAX_DEPTH=9999

# Enable/disable deletion of macOS and Windows metadata (1 or 0)
DELETE_MACOS_METADATA="1"
DELETE_WINDOWS_METADATA="1"

# Delete ._* AppleDouble resource fork files (can be many files, set to 1 to enable)
INCLUDE_RESOURCE_FORKS="0"

# 1 = preview only, 0 = delete matches
DRY_RUN="1"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

###############################################################################

_normalize_bool_flag() {
    case "$1" in
        true|True|TRUE|1) echo "1" ;;
        false|False|FALSE|0) echo "0" ;;
        *) echo "$1" ;;
    esac
}
DELETE_MACOS_METADATA=$(_normalize_bool_flag "$DELETE_MACOS_METADATA")
DELETE_WINDOWS_METADATA=$(_normalize_bool_flag "$DELETE_WINDOWS_METADATA")

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    _ui_msg="Error: LOG_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
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
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

build_file_find_args() {
    local -n args_ref=$1
    args_ref=(-type f "(")
    local need_or=0
    if [[ "$DELETE_MACOS_METADATA" == "1" ]]; then
        args_ref+=(-name ".DS_Store" -o -name "._.DS_Store" -o -name ".LSOverride" -o -name ".VolumeIcon.icns" -o -name ".com.apple.timemachine.donotpresent" -o -name ".apdisk")
        need_or=1
        if [[ "$INCLUDE_RESOURCE_FORKS" == "1" ]]; then
            args_ref+=(-o -name "._*")
        fi
    fi
    if [[ "$DELETE_WINDOWS_METADATA" == "1" ]]; then
        [[ $need_or -eq 0 ]] || args_ref+=(-o)
        args_ref+=(-name "Thumbs.db" -o -name "Thumbs.db:encryptable" -o -name "ehthumbs.db" -o -name "ehthumbs_vista.db" -o -name "desktop.ini")
    fi
    args_ref+=(")")
}

build_dir_find_args() {
    local -n args_ref=$1
    args_ref=(-type d "(" -name ".Spotlight-V100" -o -name ".Trashes" -o -name ".TemporaryItems" -o -name ".fseventsd" -o -name ".AppleDouble" ")")
}

# Validate path for safety (reject .. and - prefix)
is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    return 0
}

# Search roots must be a real subdirectory under /mnt (not /mnt itself).
is_safe_delete_path() {
    local p="$1"
    is_safe_path "$p" || return 1
    [[ "$p" == "/" || "$p" == "/mnt" ]] && return 1
    [[ "$p" == "/mnt/"* ]] && [[ "$p" != "/mnt/"*/* ]] && return 1
    return 0
}

main() {
    local total_deleted=0
    local total_matched=0

    # Validate configuration
    if [[ "$DELETE_MACOS_METADATA" != "0" && "$DELETE_MACOS_METADATA" != "1" ]]; then
        log_err "DELETE_MACOS_METADATA must be 0 or 1"
        return 1
    fi
    if [[ "$DELETE_WINDOWS_METADATA" != "0" && "$DELETE_WINDOWS_METADATA" != "1" ]]; then
        log_err "DELETE_WINDOWS_METADATA must be 0 or 1"
        return 1
    fi

    if [[ "$DELETE_MACOS_METADATA" == "0" && "$DELETE_WINDOWS_METADATA" == "0" ]]; then
        log "Both DELETE_MACOS_METADATA and DELETE_WINDOWS_METADATA are 0. Nothing to delete."
        return 0
    fi
    if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
        log_err "DRY_RUN must be 0 or 1"
        return 1
    fi

    if [[ ${#SEARCH_PATHS[@]} -eq 0 ]]; then
        log_err "SEARCH_PATHS is empty."
        return 1
    fi

    local os_types=""
    [[ "$DELETE_MACOS_METADATA" == "1" ]] && os_types="macOS"
    [[ "$DELETE_WINDOWS_METADATA" == "1" ]] && os_types="${os_types:+$os_types and }Windows"
    [[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no files or directories will be deleted"
    log "Searching for and deleting ${os_types} metadata files..."

    for base in "${SEARCH_PATHS[@]}"; do
        if ! is_safe_delete_path "$base"; then
            log_err "Skipping unsafe path (must be a subdirectory under /mnt, not /mnt itself): $base"
            continue
        fi
        if [[ ! -d "$base" ]]; then
            log "Skipping $base (not found)"
            continue
        fi

        log "Scanning: $base"
        local count=0
        local matched=0
        local file_find_args=()
        local dir_find_args=()

        if [[ "$DELETE_MACOS_METADATA" == "1" || "$DELETE_WINDOWS_METADATA" == "1" ]]; then
            build_file_find_args file_find_args
            while IFS= read -r -d '' file; do
                local basename="${file##*/}"
                if [[ "$basename" == ._* ]] && [[ "$basename" != "._.DS_Store" ]] && [[ "$INCLUDE_RESOURCE_FORKS" != "1" ]]; then
                    continue
                fi
                ((matched++))
                if [[ "$DRY_RUN" == "1" ]]; then
                    continue
                fi
                rm -f "$file" 2>/dev/null && ((count++)) || true
            done < <(find "$base" -maxdepth "$MAX_DEPTH" "${file_find_args[@]}" -print0 2>/dev/null || true)
        fi

        if [[ "$DELETE_MACOS_METADATA" == "1" ]]; then
            build_dir_find_args dir_find_args
            while IFS= read -r -d '' dir; do
                ((matched++))
                if [[ "$DRY_RUN" == "1" ]]; then
                    continue
                fi
                rm -rf "$dir" 2>/dev/null && ((count++)) || true
            done < <(find "$base" -maxdepth "$MAX_DEPTH" "${dir_find_args[@]}" -print0 2>/dev/null || true)
        fi

        ((total_matched += matched))
        ((total_deleted += count))
        if [[ "$DRY_RUN" == "1" ]]; then
            [[ $matched -gt 0 ]] && log "  Would delete $matched item(s) from $base"
        else
            [[ $count -gt 0 ]] && log "  Deleted $count item(s) from $base"
        fi
    done

    if [[ "$DRY_RUN" == "1" ]]; then
        log "Done. Total items matched: $total_matched"
    else
        log "Done. Total items deleted: $total_deleted"
    fi
}

main "$@"
