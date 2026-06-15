#!/bin/bash
#
# clear-plex-codecs.sh
# Deletes Plex Media Server codec cache to resolve codec or transcoding issues
#
# Description:
#   Removes all contents of the Plex codecs directory. Plex will re-download
#   codecs as needed. Use when troubleshooting transcoding or codec errors.
#
# Usage:
#   ./clear-plex-codecs.sh
#
# Configuration:
#   - PLEX_PATH: Host path to Plex appdata (Docker /config mapping; contains Library/…)
#   - PLEX_CODECS_PATH: Derived from PLEX_PATH unless you set it explicitly below
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
 
# Plex appdata on the host (Unraid: folder you map to the container's /config)
PLEX_PATH="/mnt/user/appdata/plexmediaserver"

# Codecs folder (leave empty = under PLEX_PATH; set full path only if yours differs)
PLEX_CODECS_PATH=""

if [[ -z "$PLEX_CODECS_PATH" ]]; then
    if [[ -z "$PLEX_PATH" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Set PLEX_PATH (appdata root) or set PLEX_CODECS_PATH to the Codecs directory." >&2
        exit 1
    fi
    PLEX_CODECS_PATH="${PLEX_PATH}/Library/Application Support/Plex Media Server/Codecs"
fi

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

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
