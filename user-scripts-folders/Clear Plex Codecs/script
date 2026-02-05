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
#   - TARGET: Path to Plex Media Server Codecs directory (edit for your appdata path)
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Plex codecs directory - EDIT FOR YOUR SETUP (common Unraid path below)
PLEX_CODECS_PATH="/mnt/user/appdata/plexmediaserver/Library/Application Support/Plex Media Server/Codecs"
TARGET="$PLEX_CODECS_PATH"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Require path to look like a Plex appdata path to reduce accidental misuse
is_safe_plex_codecs_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == "/" ]] && return 1
    [[ "$p" == "/mnt" ]] && return 1
    [[ "$p" != *[Pp]lex* ]] && return 1
    return 0
}

main() {
    if [[ ! -d "$TARGET" ]]; then
        log "Directory does not exist: $TARGET"
        return 1
    fi
    if ! is_safe_plex_codecs_path "$TARGET"; then
        log "Refusing to delete: path does not look like a Plex path (must contain 'plex'). Set PLEX_CODECS_PATH correctly."
        return 1
    fi

    log "Deleting all contents inside: $TARGET"
    rm -rf "$TARGET"/* "$TARGET"/.[!.]* "$TARGET"/..?* 2>/dev/null || true
    log "Deletion complete."
}

main "$@"
