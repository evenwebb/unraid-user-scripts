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
#   Set DRY_RUN=1 in script to preview without making changes.
#
# Configuration:
#   - PERM_PATHS: List of directories to process (edit for your mount points)
#   - OWNER_GROUP: owner:group for chown (default: nobody:users)
#   - CHMOD_FLAGS: chmod flags (default: Docker-safe, dirs 0777, files 0666)
#   - DRY_RUN: 1 = log only, no chmod/chown (default: 0)
#
# Requires: root (run with sudo)
# Note: Output goes to stdout; Unraid User Scripts captures it in the GUI.
# Note: Dangerous paths (/, /etc, /boot, etc.) are blocked. Overlapping paths
#       are deduplicated (e.g. /mnt/user and /mnt/user/Media -> only /mnt/user).
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

# Chmod flags (Docker-safe: dirs 0777, files 0666)
CHMOD_FLAGS="u-x,go-rwx,go+u,ugo+X"

# Behaviour
DRY_RUN="0"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Paths that are too dangerous to process
DANGEROUS_PATHS=("/" "/etc" "/boot" "/root" "/usr" "/var" "/bin" "/sbin" "/lib" "/lib64" "/sys" "/proc" "/dev")

is_dangerous_path() {
    local p
    p=$(readlink -f "$1" 2>/dev/null || echo "$1")
    p="${p%/}"
    for dangerous in "${DANGEROUS_PATHS[@]}"; do
        if [[ "$p" == "$dangerous" || "$p" == "$dangerous"/* ]]; then
            return 0
        fi
    done
    return 1
}

# Remove duplicates and paths that are subpaths of others (process parent only)
dedupe_paths() {
    local -a result=()
    local p q
    for p in "$@"; do
        [[ -z "$p" ]] && continue
        local skip=0
        for q in "$@"; do
            [[ -z "$q" || "$p" == "$q" ]] && continue
            if [[ "$p" == "$q"/* ]]; then
                skip=1
                break
            fi
        done
        [[ $skip -eq 1 ]] && continue
        local seen=0
        for q in "${result[@]}"; do
            [[ "$p" == "$q" ]] && { seen=1; break; }
        done
        [[ $seen -eq 0 ]] && result+=("$p")
    done
    printf '%s\n' "${result[@]}"
}

main() {
    if [[ "${#PERM_PATHS[@]}" -eq 0 ]]; then
        log_err "PERM_PATHS is empty. Add directories to process."
        exit 1
    fi

    if [[ "$(id -u)" -ne 0 ]]; then
        log_err "Must run as root (e.g. sudo)."
        exit 1
    fi

    local -a paths_to_process
    mapfile -t paths_to_process < <(dedupe_paths "${PERM_PATHS[@]}")
    if [[ ${#paths_to_process[@]} -lt ${#PERM_PATHS[@]} ]]; then
        log "Skipped overlapping paths (processing parent directories only)"
    fi

    [[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no changes will be made"

    local any_failed=0
    for path in "${paths_to_process[@]}"; do
        [[ -z "$path" ]] && continue

        if [[ ! -d "$path" ]]; then
            log "Skipping $path (not found)"
            continue
        fi

        if is_dangerous_path "$path"; then
            log_err "Skipping $path (path is not allowed for safety)"
            any_failed=1
            continue
        fi

        log "Applying permissions to: $path"

        if [[ "$DRY_RUN" == "1" ]]; then
            log "[DRY-RUN] would run: chmod -R $CHMOD_FLAGS $path"
            log "[DRY-RUN] would run: chown -R $OWNER_GROUP $path"
            continue
        fi

        if ! chmod -R $CHMOD_FLAGS "$path"; then
            log_err "chmod failed for $path"
            any_failed=1
            continue
        fi

        if ! chown -R "$OWNER_GROUP" "$path"; then
            log_err "chown failed for $path"
            any_failed=1
            continue
        fi
    done

    if [[ "$DRY_RUN" != "1" && "$any_failed" -eq 0 ]]; then
        sync
    fi

    if [[ "$any_failed" -eq 1 ]]; then
        log_err "Completed with errors"
        exit 1
    fi

    log "New permissions complete."
}

main "$@"
