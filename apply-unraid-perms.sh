#!/bin/bash
#
# apply-unraid-perms.sh
# Apply Unraid-style permissions (nobody:users, Docker-safe) to configured paths.
#
# Description:
#   Recursively chmod/chown paths for Unraid shares and Docker.
#   Can take a long time on large arrays - check PERM_PATHS before running.
#
# Usage:
#   ./apply-unraid-perms.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only (default), 0 = apply changes
#
# Configuration (edit script variables below):
#   - PERM_PATHS: directories to process
#   - OWNER_GROUP: chown target (default nobody:users)
#   - CHMOD_FLAGS: chmod flags (Docker-safe defaults)
#   - EXCLUDE_PATHS: globs to skip inside PERM_PATHS
#   - PARALLEL_JOBS: parallel xargs jobs (0 = sequential)
#   - DRY_RUN: 1 = preview only (default), 0 = apply changes
#
# Requires: root (run with sudo)
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

# Directories to apply new permissions
PERM_PATHS=(
    "/mnt/user"
    "/mnt/appdata"
    "/mnt/downloads"
)

# Owner:group (Unraid default)
OWNER_GROUP="nobody:users"

# Chmod flags (Docker-safe: dirs 0777, files 0666).
# Warning: u-x removes execute bits from regular files; ugo+X only restores execute on directories.
CHMOD_FLAGS=(u-x,go-rwx,go+u,ugo+X)

# Behavior
DRY_RUN="1"             # 1 = preview only, 0 = apply chmod changes

# Paths to skip within PERM_PATHS (e.g. "*/Downloads/*" or "*/system/docker/*")
# Glob patterns are matched against full file paths via find -path
EXCLUDE_PATHS=()

# Number of parallel jobs (0 = sequential chmod -R, >0 = xargs -P parallel)
# Parallel mode is faster on large arrays but may stress disk I/O
PARALLEL_JOBS="0"

###############################################################################

# Support merged configs that still have CHMOD_FLAGS as a plain string.
if [[ "${CHMOD_FLAGS[*]}" == "${CHMOD_FLAGS[0]:-}" ]] && [[ "${#CHMOD_FLAGS[@]}" -eq 1 ]]; then
    IFS=',' read -ra CHMOD_FLAGS <<< "${CHMOD_FLAGS[0]}"
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
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

# Reject paths that are too shallow (e.g. /mnt/user alone) - same minimum depth as is_safe_delete_path.
is_safe_perm_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    [[ "$p" == "/" || "$p" == "/mnt" ]] && return 1
    [[ "$p" == "/mnt/"* ]] && [[ "$p" != "/mnt/"*/* ]] && return 1
    return 0
}

# Remove duplicates and paths that are subpaths of others (process parent only).
# Uses an associative array for O(n * depth) lookup instead of O(n^2).
dedupe_paths() {
    local -A path_set=()
    local -a sorted=()
    local p parent

    # Build set of all input paths
    for p in "$@"; do
        [[ -z "$p" ]] && continue
        path_set["$p"]=1
    done

    # Sort paths by length (shorter paths first - parents come before children)
    for p in "${!path_set[@]}"; do
        sorted+=("$p")
    done
    # Simple bubble-like insertion for few paths (typically 2-5 entries)
    local i j tmp
    for ((i = 0; i < ${#sorted[@]}; i++)); do
        for ((j = i + 1; j < ${#sorted[@]}; j++)); do
            if [[ ${#sorted[j]} -lt ${#sorted[i]} ]]; then
                tmp="${sorted[i]}"
                sorted[i]="${sorted[j]}"
                sorted[j]="$tmp"
            fi
        done
    done

    local -a result=()
    local -A parent_seen=()
    for p in "${sorted[@]}"; do
        # Check if any parent path already in result
        parent="$p"
        local is_child=0
        while [[ "$parent" != "/" && "$parent" != "." ]]; do
            parent="${parent%/*}"
            [[ -n "${parent_seen[$parent]:-}" ]] && { is_child=1; break; }
        done
        if [[ $is_child -eq 0 ]]; then
            parent_seen["$p"]=1
            result+=("$p")
        fi
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

        if ! is_safe_perm_path "$path"; then
            log_err "Skipping $path (path is too shallow - use a subdirectory, e.g. /mnt/user/downloads/...)"
            any_failed=1
            continue
        fi

        log "Applying permissions to: $path"

        # Build exclude args for find
        local exclude_args=()
        local ep
        for ep in "${EXCLUDE_PATHS[@]}"; do
            [[ -z "$ep" ]] && continue
            exclude_args+=(-not -path "$ep")
        done

        if [[ "$DRY_RUN" == "1" ]]; then
            local file_count
            file_count=$(find "$path" -xdev -type f "${exclude_args[@]}" 2>/dev/null | wc -l | tr -d '[:space:]')
            [[ "$file_count" != *[0-9]* ]] && file_count=0
            log "[DRY-RUN] would apply: chmod ${CHMOD_FLAGS[*]} / chown $OWNER_GROUP on $path"
            log "[DRY-RUN] would touch approximately $file_count file(s) under $path"
            [[ ${#exclude_args[@]} -gt 0 ]] && log "[DRY-RUN] exclude patterns: ${EXCLUDE_PATHS[*]}"
            [[ "$PARALLEL_JOBS" -gt 0 ]] && log "[DRY-RUN] parallel mode: $PARALLEL_JOBS jobs"
            continue
        fi

        if [[ "$PARALLEL_JOBS" -gt 0 ]] && [[ "$PARALLEL_JOBS" =~ ^[0-9]+$ ]]; then
            # Parallel mode: use find + xargs -P for faster processing on large dirs
            find "$path" -xdev -type d "${exclude_args[@]}" -print0 2>/dev/null | \
                xargs -0 -P "$PARALLEL_JOBS" -n 50 chmod "${CHMOD_FLAGS[@]}" 2>/dev/null || true
            find "$path" -xdev -type f "${exclude_args[@]}" -print0 2>/dev/null | \
                xargs -0 -P "$PARALLEL_JOBS" -n 100 chmod "${CHMOD_FLAGS[@]}" 2>/dev/null || true
            find "$path" -xdev "${exclude_args[@]}" -print0 2>/dev/null | \
                xargs -0 -P "$PARALLEL_JOBS" -n 100 chown "$OWNER_GROUP" -- 2>/dev/null || true
            log "Parallel permissions applied to $path"
        else
            # Sequential mode (original chmod -R behavior)
            if [[ ${#exclude_args[@]} -gt 0 ]]; then
                find "$path" -xdev "${exclude_args[@]}" -exec chmod "${CHMOD_FLAGS[@]}" {} + 2>/dev/null || true
                find "$path" -xdev "${exclude_args[@]}" -exec chown "$OWNER_GROUP" -- {} + 2>/dev/null || true
            else
                if ! chmod -R -- "${CHMOD_FLAGS[@]}" "$path"; then
                    log_err "chmod failed for $path"
                    any_failed=1
                    continue
                fi
                if ! chown -R "$OWNER_GROUP" "$path"; then
                    log_err "chown failed for $path"
                    any_failed=1
                    continue
                fi
            fi
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
