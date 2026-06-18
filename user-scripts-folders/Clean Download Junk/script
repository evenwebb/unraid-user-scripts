#!/bin/bash
#
# clean-download-junk.sh
# Remove download junk files and empty folders (NZB, torrent, or both).
#
# Description:
#   Choose a profile for preset paths and junk patterns, or use custom with your own FOLDERS list.
#
# Usage:
#   ./clean-download-junk.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   PROFILE: nzb, torrent, all, or custom
#   DRY_RUN: 1 = preview only (default), 0 = delete files
#
# Configuration (edit script variables below):
#   - PROFILE: nzb | torrent | all | custom
#   - FOLDERS / JUNK_EXTENSIONS: used when PROFILE=custom (or override profile defaults)
#   - EXTRA_FOLDERS / EXTRA_JUNK_EXTENSIONS: append to any profile
#   - MIN_AGE_MINUTES, EXCLUDE_PATTERNS, DELETE_SAMPLES, DELETE_EMPTY_DIRS
#   - DRY_RUN: 1 = preview only (default), 0 = delete files
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

# Profile presets:
#   nzb     — Usenet/NZBGet completed download paths + NZB junk patterns
#   torrent — torrent client completed paths + torrent junk patterns
#   all     — both NZB and torrent presets combined (deduped)
#   custom  — use FOLDERS and JUNK_EXTENSIONS below only
PROFILE="all"

# 1 = dry-run (no deletions), 0 = production
DRY_RUN="1"

# Skip files modified less than N minutes ago (0 = no minimum age)
MIN_AGE_MINUTES="5"

# Glob patterns to exclude from deletion (e.g. "*.nfo" to keep metadata files)
EXCLUDE_PATTERNS=()

# Override profile folders (non-empty replaces profile folder list)
FOLDERS=()

# Override profile junk patterns (non-empty replaces profile extension list)
JUNK_EXTENSIONS=()

# Append to profile folders / patterns regardless of profile
EXTRA_FOLDERS=()
EXTRA_JUNK_EXTENSIONS=()

# 1 = remove *sample* files and sample/samples directories, 0 = skip
DELETE_SAMPLES="1"

# 1 = remove empty directories after cleanup, 0 = skip
DELETE_EMPTY_DIRS="1"

###############################################################################

# --- Profile: NZB ---
_PROFILE_NZB_FOLDERS=(
    "/mnt/user/downloads/complete/tv"
    "/mnt/user/downloads/complete/movies"
)

_PROFILE_NZB_EXTENSIONS=(
    "*.nzb"
)

# --- Profile: torrent ---
_PROFILE_TORRENT_FOLDERS=(
    "/mnt/user/downloads/complete/torrents"
    "/mnt/user/downloads/complete/movies"
    "/mnt/user/downloads/complete/tv"
)

_PROFILE_TORRENT_EXTENSIONS=(
    "*.torrent"
    "*.!ut" "*.!utpart"
    "*.bc!"
    "*.!qb"
    "*.!sync" "*.!bt"
    "*.pad"
    "*.tmp" "*.temp"
    "*.crc" "*.crc32"
)

# --- Shared junk patterns (NZB + torrent) ---
_PROFILE_COMMON_EXTENSIONS=(
    "*.nfo"
    "*.sfv" "*.srs" "*.srr"
    "*.url"
    "*.html" "*.htm"
    "*.log" "*.txt"
    "*.par2" "*.vol*.par2"
    "*.md5" "*.lnk"
    "*.m3u" "*.m3u8"
    "*.jpg" "*.jpeg" "*.png" "*.gif" "*.bmp"
    "*.exe" "*.com" "*.bat" "*.cmd" "*.scr" "*.dll"
    "*.rar" "*.r[0-9]" "*.r[0-9][0-9]"
    "*.zip" "*.7z"
    ".DS_Store" "Thumbs.db"
)

ACTIVE_FOLDERS=()
ACTIVE_JUNK_EXTENSIONS=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
}

is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* ]] && return 1
    return 0
}

_array_append_unique() {
    local -n _dest_ref="$1"
    local item
    for item in "${@:2}"; do
        [[ -z "$item" ]] && continue
        local existing
        for existing in "${_dest_ref[@]}"; do
            [[ "$existing" == "$item" ]] && continue 2
        done
        _dest_ref+=("$item")
    done
}

resolve_profile_config() {
    ACTIVE_FOLDERS=()
    ACTIVE_JUNK_EXTENSIONS=()

    local profile_lower="${PROFILE,,}"

    case "$profile_lower" in
        nzb)
            _array_append_unique ACTIVE_FOLDERS "${_PROFILE_NZB_FOLDERS[@]}"
            _array_append_unique ACTIVE_JUNK_EXTENSIONS "${_PROFILE_COMMON_EXTENSIONS[@]}"
            _array_append_unique ACTIVE_JUNK_EXTENSIONS "${_PROFILE_NZB_EXTENSIONS[@]}"
            ;;
        torrent)
            _array_append_unique ACTIVE_FOLDERS "${_PROFILE_TORRENT_FOLDERS[@]}"
            _array_append_unique ACTIVE_JUNK_EXTENSIONS "${_PROFILE_COMMON_EXTENSIONS[@]}"
            _array_append_unique ACTIVE_JUNK_EXTENSIONS "${_PROFILE_TORRENT_EXTENSIONS[@]}"
            ;;
        all)
            _array_append_unique ACTIVE_FOLDERS "${_PROFILE_NZB_FOLDERS[@]}"
            _array_append_unique ACTIVE_FOLDERS "${_PROFILE_TORRENT_FOLDERS[@]}"
            _array_append_unique ACTIVE_JUNK_EXTENSIONS "${_PROFILE_COMMON_EXTENSIONS[@]}"
            _array_append_unique ACTIVE_JUNK_EXTENSIONS "${_PROFILE_NZB_EXTENSIONS[@]}"
            _array_append_unique ACTIVE_JUNK_EXTENSIONS "${_PROFILE_TORRENT_EXTENSIONS[@]}"
            ;;
        custom)
            ;;
        *)
            log_err "PROFILE must be nzb, torrent, all, or custom (you entered: ${PROFILE})."
            return 1
            ;;
    esac

    if [[ ${#FOLDERS[@]} -gt 0 ]]; then
        ACTIVE_FOLDERS=()
        _array_append_unique ACTIVE_FOLDERS "${FOLDERS[@]}"
    elif [[ "$profile_lower" == "custom" ]]; then
        log_err "PROFILE is custom but FOLDERS is empty. Add paths or choose another profile."
        return 1
    fi

    if [[ ${#JUNK_EXTENSIONS[@]} -gt 0 ]]; then
        ACTIVE_JUNK_EXTENSIONS=()
        _array_append_unique ACTIVE_JUNK_EXTENSIONS "${JUNK_EXTENSIONS[@]}"
    elif [[ "$profile_lower" == "custom" && ${#JUNK_EXTENSIONS[@]} -eq 0 && ${#EXTRA_JUNK_EXTENSIONS[@]} -eq 0 ]]; then
        log_err "PROFILE is custom but JUNK_EXTENSIONS and EXTRA_JUNK_EXTENSIONS are both empty."
        return 1
    fi

    _array_append_unique ACTIVE_FOLDERS "${EXTRA_FOLDERS[@]}"
    _array_append_unique ACTIVE_JUNK_EXTENSIONS "${EXTRA_JUNK_EXTENSIONS[@]}"

    if [[ ${#ACTIVE_FOLDERS[@]} -eq 0 ]]; then
        log_err "No folders to process after resolving PROFILE=${PROFILE}."
        return 1
    fi
    if [[ ${#ACTIVE_JUNK_EXTENSIONS[@]} -eq 0 ]]; then
        log_err "No junk patterns configured after resolving PROFILE=${PROFILE}."
        return 1
    fi

    log "Profile: ${PROFILE} — ${#ACTIVE_FOLDERS[@]} folder(s), ${#ACTIVE_JUNK_EXTENSIONS[@]} junk pattern(s)"
    return 0
}

_build_extra_find_args() {
    local result=()
    if [[ "$MIN_AGE_MINUTES" -gt 0 ]] && [[ "$MIN_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
        result+=(-mmin "+${MIN_AGE_MINUTES}")
    fi
    local ep
    for ep in "${EXCLUDE_PATTERNS[@]}"; do
        [[ -z "$ep" ]] && continue
        result+=(! -iname "$ep")
    done
    printf '%s\n' "${result[@]}"
}

delete_junk_files() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        log "Skipping $dir (not found)"
        return 0
    fi

    log "Scanning for junk files in: $dir"

    local find_args=()
    local added=0
    local has_r_splits=0
    local p lower
    for p in "${ACTIVE_JUNK_EXTENSIONS[@]}"; do
        [[ -z "$p" ]] && continue
        lower="${p,,}"
        if [[ "$lower" == ".r[0-9]" || "$lower" == ".r[0-9][0-9]" ]]; then
            has_r_splits=1
            continue
        fi
        if [[ $added -gt 0 ]]; then
            find_args+=(-o)
        fi
        find_args+=(-iname "$p")
        added=1
    done

    if [[ $has_r_splits -eq 1 ]]; then
        if [[ $added -gt 0 ]]; then
            find_args+=(-o)
        fi
        find_args+=(-iregex '.*\.r[0-9]+')
        added=1
    fi

    if [[ $added -eq 0 ]]; then
        log "No junk patterns configured."
        return 0
    fi

    local extra_args=()
    while IFS= read -r arg; do
        [[ -n "$arg" ]] && extra_args+=("$arg")
    done < <(_build_extra_find_args)

    local count
    if [[ "$DRY_RUN" == "1" ]]; then
        count=$(find "$dir" -xdev -type f "${extra_args[@]}" \( "${find_args[@]}" \) -print 2>/dev/null | wc -l)
        log "Found $count junk file(s) (dry run)"
    else
        count=$(find "$dir" -xdev -type f "${extra_args[@]}" \( "${find_args[@]}" \) -delete -print 2>/dev/null | wc -l)
        log "Deleted $count junk file(s)"
    fi
}

delete_sample_files() {
    local dir="$1"

    [[ "$DELETE_SAMPLES" == "1" ]] || return 0
    [[ -d "$dir" ]] || return 0

    log "Scanning for sample files in: $dir"

    local extra_args=()
    while IFS= read -r arg; do
        [[ -n "$arg" ]] && extra_args+=("$arg")
    done < <(_build_extra_find_args)

    local count
    if [[ "$DRY_RUN" == "1" ]]; then
        count=$(find "$dir" -xdev -type f "${extra_args[@]}" -iname "*sample*" -print 2>/dev/null | wc -l)
        log "Found $count sample file(s) (dry run)"
    else
        count=$(find "$dir" -xdev -type f "${extra_args[@]}" -iname "*sample*" -delete -print 2>/dev/null | wc -l)
        log "Deleted $count sample file(s)"
    fi
}

delete_sample_dirs() {
    local dir="$1"

    [[ "$DELETE_SAMPLES" == "1" ]] || return 0
    [[ -d "$dir" ]] || return 0

    log "Scanning for sample directories in: $dir"

    local count
    if [[ "$DRY_RUN" == "1" ]]; then
        count=$(find "$dir" -xdev -type d \( -iname "sample" -o -iname "samples" \) -print 2>/dev/null | wc -l)
        log "Found $count sample director(ies) (dry run)"
    else
        count=$(find "$dir" -xdev -type d \( -iname "sample" -o -iname "samples" \) -print 2>/dev/null | wc -l)
        if [[ $count -gt 0 ]]; then
            find "$dir" -xdev -type d \( -iname "sample" -o -iname "samples" \) -exec rm -rf {} + 2>/dev/null || true
        fi
        log "Deleted $count sample director(ies)"
    fi
}

delete_empty_dirs() {
    local dir="$1"
    local total=0
    local pass=0

    [[ "$DELETE_EMPTY_DIRS" == "1" ]] || return 0
    [[ -d "$dir" ]] || return 0

    log "Cleaning empty directories in: $dir"

    if [[ "$DRY_RUN" == "1" ]]; then
        while IFS= read -r -d '' empty_dir; do
            ((total++)) || true
        done < <(find "$dir" -xdev -type d -empty -print0 2>/dev/null || true)
        log "Found $total empty director(ies) (dry run)"
        return 0
    fi

    while true; do
        local count=0
        ((pass++)) || true

        while IFS= read -r -d '' empty_dir; do
            rmdir "$empty_dir" 2>/dev/null && ((count++)) || true
        done < <(find "$dir" -xdev -type d -empty -print0 2>/dev/null || true)

        [[ $count -eq 0 ]] && break

        ((total += count)) || true
        [[ $count -gt 0 ]] && log "  Pass $pass: removed $count empty director(ies)"
    done

    log "Removed $total empty director(ies) total"
}

main() {
    local start_time
    start_time=$(date +%s)

    if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
        log_err "DRY_RUN must be 0 or 1."
        return 1
    fi
    if [[ "$DELETE_SAMPLES" != "0" && "$DELETE_SAMPLES" != "1" ]]; then
        log_err "DELETE_SAMPLES must be 0 or 1."
        return 1
    fi
    if [[ "$DELETE_EMPTY_DIRS" != "0" && "$DELETE_EMPTY_DIRS" != "1" ]]; then
        log_err "DELETE_EMPTY_DIRS must be 0 or 1."
        return 1
    fi

    resolve_profile_config || return 1

    [[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no files or directories will be deleted"

    for folder in "${ACTIVE_FOLDERS[@]}"; do
        if ! is_safe_path "$folder"; then
            log_err "Skipping unsafe path: $folder"
            continue
        fi
        log "Processing: $folder"
        delete_junk_files "$folder"
        delete_sample_files "$folder"
        delete_sample_dirs "$folder"
        delete_empty_dirs "$folder"
        log "Completed: $folder"
        echo ""
    done

    local duration=$(( $(date +%s) - start_time ))
    log "Cleanup completed in ${duration}s"
}

main "$@"
