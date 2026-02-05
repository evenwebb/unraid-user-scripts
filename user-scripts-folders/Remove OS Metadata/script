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
#   - DELETE_MACOS_METADATA: Set to "true" to delete macOS files, "false" to skip (default: true)
#   - DELETE_WINDOWS_METADATA: Set to "true" to delete Windows files, "false" to skip (default: true)
#   - INCLUDE_RESOURCE_FORKS: Set to 1 to also delete ._* files (default: 0, can be large)
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

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

main() {
    local total_deleted=0

    # Validate configuration
    if [[ "$DELETE_MACOS_METADATA" != "true" && "$DELETE_MACOS_METADATA" != "false" ]]; then
        log "Error: DELETE_MACOS_METADATA must be 'true' or 'false'"
        return 1
    fi
    if [[ "$DELETE_WINDOWS_METADATA" != "true" && "$DELETE_WINDOWS_METADATA" != "false" ]]; then
        log "Error: DELETE_WINDOWS_METADATA must be 'true' or 'false'"
        return 1
    fi

    if [[ "$DELETE_MACOS_METADATA" == "false" && "$DELETE_WINDOWS_METADATA" == "false" ]]; then
        log "Both DELETE_MACOS_METADATA and DELETE_WINDOWS_METADATA are set to false. Nothing to delete. Exiting."
        return 0
    fi

    local os_types=""
    [[ "$DELETE_MACOS_METADATA" == "true" ]] && os_types="macOS"
    [[ "$DELETE_WINDOWS_METADATA" == "true" ]] && os_types="${os_types:+$os_types and }Windows"
    log "Searching for and deleting ${os_types} metadata files..."

    for base in "${SEARCH_PATHS[@]}"; do
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
            \) -print0 2>/dev/null)

            # Delete AppleDouble resource fork files (._*) if enabled
            if [[ "$INCLUDE_RESOURCE_FORKS" == "1" ]]; then
                while IFS= read -r -d '' file; do
                    # Match ._* but exclude ._.DS_Store (already handled above)
                    local basename="${file##*/}"
                    if [[ "$basename" == ._* ]] && [[ "$basename" != "._.DS_Store" ]]; then
                        rm -f "$file" 2>/dev/null && ((count++)) || true
                    fi
                done < <(find "$base" -maxdepth "$MAX_DEPTH" -type f -name "._*" -print0 2>/dev/null)
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
            \) -print0 2>/dev/null)
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
            \) -print0 2>/dev/null)
        fi

        ((total_deleted += count))
        [[ $count -gt 0 ]] && log "  Deleted $count item(s) from $base"
    done

    log "Done. Total items deleted: $total_deleted"
}

main "$@"
