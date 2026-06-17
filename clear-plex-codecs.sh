#!/bin/bash
#
# clear-plex-codecs.sh
# Delete Plex codec cache (Plex re-downloads as needed).
#
# Description:
#   Frees space under PLEX_CODECS_PATH. Plex may briefly re-transcode after clearing.
#
# Usage:
#   ./clear-plex-codecs.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - PLEX_PATH: Plex appdata root (used when PLEX_CODECS_PATH is empty)
#   - PLEX_CODECS_PATH: codec cache directory (empty = under PLEX_PATH)
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
 
# Plex appdata on the host (Unraid: folder you map to the container's /config)
PLEX_PATH="/mnt/user/appdata/plexmediaserver"

# Codecs folder (leave empty = under PLEX_PATH; set full path only if yours differs)
PLEX_CODECS_PATH=""

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
    echo "$msg" >&2
}

if [[ -z "$PLEX_CODECS_PATH" ]]; then
    if [[ -z "$PLEX_PATH" ]]; then
        log_err "Set PLEX_PATH (appdata root) or set PLEX_CODECS_PATH to the Codecs directory."
        exit 1
    fi
    PLEX_CODECS_PATH="${PLEX_PATH}/Library/Application Support/Plex Media Server/Codecs"
fi

# Require path to look like a Plex appdata path to reduce accidental misuse
is_safe_plex_codecs_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    [[ "$p" == "/" ]] && return 1
    [[ "$p" == "/mnt" ]] && return 1
    [[ "$p" != *[Pp]lex* ]] && return 1
    return 0
}

main() {
    if ! is_safe_plex_codecs_path "$PLEX_CODECS_PATH"; then
        log_err "Refusing to delete: path does not look like a Plex path (must contain 'plex'). Set PLEX_PATH / PLEX_CODECS_PATH correctly."
        return 1
    fi
    if [[ ! -d "$PLEX_CODECS_PATH" ]]; then
        log "Directory does not exist (nothing to do): $PLEX_CODECS_PATH"
        return 0
    fi

    log "Deleting all contents inside: $PLEX_CODECS_PATH"
    local found=0
    shopt -s nullglob
    local items=()
    for g in "$PLEX_CODECS_PATH"/* "$PLEX_CODECS_PATH"/.[!.]* "$PLEX_CODECS_PATH"/..?*; do
        items+=("$g")
    done
    shopt -u nullglob
    found=${#items[@]}
    if [[ $found -eq 0 ]]; then
        log "No items found to delete in $PLEX_CODECS_PATH"
    else
        local fail=0
        for item in "${items[@]}"; do
            rm -rf "$item" 2>/dev/null || { log_err "Failed to delete: $item"; fail=1; }
        done
        if [[ $fail -eq 0 ]]; then
            log "Deletion complete ($found item(s) removed)."
        else
            log_err "Deletion completed with errors; some items may not have been removed."
        fi
    fi
}

main "$@"
