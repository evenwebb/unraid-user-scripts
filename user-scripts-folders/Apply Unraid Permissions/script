#!/bin/bash
#
# apply-unraid-perms.sh
# Applies Unraid-style "new permissions" (Docker-safe) to array and appdata paths
#
# Description:
#   Recursively sets chmod/chown on configured paths to nobody:users with
#   permissions suitable for Unraid shares and Docker. Run after adding
#   new files or when permission issues occur.
#   WARNING: Can run for a long time on large arrays; ensure PERM_PATHS are correct.
#
# Usage:
#   ./apply-unraid-perms.sh
#
# Configuration:
#   - PERM_PATHS: List of directories to process (edit for your mount points)
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Directories to apply new permissions - EDIT FOR YOUR SETUP
PERM_PATHS=(
    "/mnt/user"
    "/mnt/appdata"
    "/mnt/downloads"
)

# Owner:group (Unraid default)
OWNER_GROUP="nobody:users"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

main() {
    for path in "${PERM_PATHS[@]}"; do
        if [[ ! -d "$path" ]]; then
            log "Skipping $path (not found)"
            continue
        fi
        log "Applying permissions to: $path"
        chmod -R u-x,go-rwx,go+u,ugo+X "$path"
        chown -R "$OWNER_GROUP" "$path"
        sync
    done
    log "New permissions complete."
}

main "$@"
