#!/bin/bash
#
# remove-os-metadata.sh
# Removes macOS and Windows metadata files from configured paths
#
# Description:
#   Finds and deletes macOS and Windows metadata files that are unnecessary on Unraid/Linux.
#
#   macOS files removed:
#     - .DS_Store (folder view settings)
#     - ._.DS_Store (AppleDouble companion files)
#     - ._* (AppleDouble resource forks)
#     - .AppleDouble (AppleDouble directories)
#     - .LSOverride (Launch Services)
#     - .Spotlight-V100 (Spotlight index directories)
#     - .Trashes (Trash directories)
#     - .TemporaryItems (Temporary items)
#     - .fseventsd (File system events)
#     - .VolumeIcon.icns (Custom volume icons)
#     - .com.apple.timemachine.donotpresent (Time Machine markers)
#     - .apdisk (AFP metadata)
#
#   Windows files removed:
#     - Thumbs.db (thumbnail cache)
#     - Thumbs.db:encryptable (encrypted thumbnail cache)
#     - ehthumbs.db (Explorer thumbnail cache)
#     - ehthumbs_vista.db (Vista thumbnail cache)
#     - desktop.ini (folder customization)
#
# Usage:
#   ./remove-os-metadata.sh
#
# Configuration:
#   - SEARCH_PATHS: Directories to search (edit for your shares)
#   - MAX_DEPTH: Maximum find depth (0 = unlimited, default 9999)
#   - DELETE_MACOS_METADATA: "true" or "false" (default: true)
#   - DELETE_WINDOWS_METADATA: "true" or "false" (default: true)
#   - INCLUDE_RESOURCE_FORKS: 1 to delete ._* files (default: 0, can be large)
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#
# Note: Output goes to stdout; Unraid User Scripts captures it in the GUI.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Directories to search - EDIT FOR YOUR SETUP
SEARCH_PATHS=(
    "/mnt/user"
    "/mnt/appdata"
    "/mnt/downloads"
)

# Maximum depth (0 = unlimited). Use a number to limit depth.
MAX_DEPTH=9999

# Enable/disable deletion of macOS and Windows metadata (true/false)
DELETE_MACOS_METADATA="true"
DELETE_WINDOWS_METADATA="true"

# Delete ._* AppleDouble resource fork files (can be many files, set to 1 to enable)
INCLUDE_RESOURCE_FORKS="0"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid." >&2
    exit 1
fi

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

# Validate path for safety (reject .. and - prefix)
is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    return 0
}

main() {
    local total_deleted=0

    # Validate configuration
    if [[ "$DELETE_MACOS_METADATA" != "true" && "$DELETE_MACOS_METADATA" != "false" ]]; then
        log_err "DELETE_MACOS_METADATA must be 'true' or 'false'"
        return 1
    fi
    if [[ "$DELETE_WINDOWS_METADATA" != "true" && "$DELETE_WINDOWS_METADATA" != "false" ]]; then
        log_err "DELETE_WINDOWS_METADATA must be 'true' or 'false'"
        return 1
    fi

    if [[ "$DELETE_MACOS_METADATA" == "false" && "$DELETE_WINDOWS_METADATA" == "false" ]]; then
        log "Both DELETE_MACOS_METADATA and DELETE_WINDOWS_METADATA are false. Nothing to delete."
        return 0
    fi

    if [[ ${#SEARCH_PATHS[@]} -eq 0 ]]; then
        log_err "SEARCH_PATHS is empty."
        return 1
    fi

    local os_types=""
    [[ "$DELETE_MACOS_METADATA" == "true" ]] && os_types="macOS"
    [[ "$DELETE_WINDOWS_METADATA" == "true" ]] && os_types="${os_types:+$os_types and }Windows"
    log "Searching for and deleting ${os_types} metadata files..."

    for base in "${SEARCH_PATHS[@]}"; do
        if ! is_safe_path "$base"; then
            log_err "Skipping unsafe path: $base"
            continue
        fi
        if [[ ! -d "$base" ]]; then
            log "Skipping $base (not found)"
            continue
        fi

        log "Scanning: $base"
        local count=0

        # Delete macOS metadata files if enabled
        if [[ "$DELETE_MACOS_METADATA" == "true" ]]; then
            while IFS= read -r -d '' file; do
                rm -f "$file" 2>/dev/null && ((count++)) || true
            done < <(find "$base" -maxdepth "$MAX_DEPTH" -type f \( \
                -name ".DS_Store" -o \
                -name "._.DS_Store" -o \
                -name ".LSOverride" -o \
                -name ".VolumeIcon.icns" -o \
                -name ".com.apple.timemachine.donotpresent" -o \
                -name ".apdisk" \
            \) -print0 2>/dev/null || true)

            # Delete AppleDouble resource fork files (._*) if enabled
            if [[ "$INCLUDE_RESOURCE_FORKS" == "1" ]]; then
                while IFS= read -r -d '' file; do
                    local basename="${file##*/}"
                    if [[ "$basename" == ._* ]] && [[ "$basename" != "._.DS_Store" ]]; then
                        rm -f "$file" 2>/dev/null && ((count++)) || true
                    fi
                done < <(find "$base" -maxdepth "$MAX_DEPTH" -type f -name "._*" -print0 2>/dev/null || true)
            fi

            # Delete macOS metadata directories
            while IFS= read -r -d '' dir; do
                rm -rf "$dir" 2>/dev/null && ((count++)) || true
            done < <(find "$base" -maxdepth "$MAX_DEPTH" -type d \( \
                -name ".Spotlight-V100" -o \
                -name ".Trashes" -o \
                -name ".TemporaryItems" -o \
                -name ".fseventsd" -o \
                -name ".AppleDouble" \
            \) -print0 2>/dev/null || true)
        fi

        # Delete Windows metadata files if enabled
        if [[ "$DELETE_WINDOWS_METADATA" == "true" ]]; then
            while IFS= read -r -d '' file; do
                rm -f "$file" 2>/dev/null && ((count++)) || true
            done < <(find "$base" -maxdepth "$MAX_DEPTH" -type f \( \
                -name "Thumbs.db" -o \
                -name "Thumbs.db:encryptable" -o \
                -name "ehthumbs.db" -o \
                -name "ehthumbs_vista.db" -o \
                -name "desktop.ini" \
            \) -print0 2>/dev/null || true)
        fi

        ((total_deleted += count))
        [[ $count -gt 0 ]] && log "  Deleted $count item(s) from $base"
    done

    log "Done. Total items deleted: $total_deleted"
}

main "$@"
