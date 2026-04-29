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
#   - PLEX_CODECS_PATH: Path to Plex Media Server Codecs directory (edit for your appdata path)
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

# Plex codecs directory (common Unraid path below)
PLEX_CODECS_PATH="/mnt/user/appdata/plexmediaserver/Library/Application Support/Plex Media Server/Codecs"

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
        log_err "Refusing to delete: path does not look like a Plex path (must contain 'plex'). Set PLEX_CODECS_PATH correctly."
        return 1
    fi
    if [[ ! -d "$PLEX_CODECS_PATH" ]]; then
        log_err "Directory does not exist: $PLEX_CODECS_PATH"
        return 1
    fi

    log "Deleting all contents inside: $PLEX_CODECS_PATH"
    rm -rf "$PLEX_CODECS_PATH"/* "$PLEX_CODECS_PATH"/.[!.]* "$PLEX_CODECS_PATH"/..?* 2>/dev/null || true
    log "Deletion complete."
}

main "$@"
