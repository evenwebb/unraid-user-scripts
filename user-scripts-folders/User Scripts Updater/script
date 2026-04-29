#!/bin/bash
#
# user-scripts-updater.sh
# Updates Unraid User Scripts folders from GitHub ZIP (or local repo) while preserving local config edits.
#
# Description:
#   Designed for Unraid's "User Scripts" plugin folder structure. This script updates
#   script folders from either:
#   - a GitHub ZIP download (no git required), or
#   - a local checkout directory
#   and merges each script's editable config section so your customized variables
#   survive upgrades. New variables added upstream are automatically included using
#   upstream defaults.
#
# Usage:
#   Run from the Unraid User Scripts plugin (foreground first, then schedule).
#
# Configuration (edit script variables below):
#   - SOURCE_MODE: "zip" (download) or "local" (use REPO_DIR)
#   - ZIP_URL: GitHub ZIP URL when SOURCE_MODE="zip"
#   - REPO_DIR: Path to a local checkout when SOURCE_MODE="local"
#   - DEST_DIR: Unraid User Scripts plugin scripts dir
#   - FETCH_UPDATES: 1 to fetch a fresh ZIP each run (recommended), 0 to reuse cache
#   - DRY_RUN: 1 = show actions only, 0 = apply changes
#   - BACKUP_DIR: Where to store backups of replaced scripts
#   - WORK_DIR: Where to store ZIP cache and extraction
#
# Notes:
#   - This script expects source folders in: user-scripts-folders/
#   - It preserves config for scripts that contain an editable config marker.
#   - If a script has no marker, it will be overwritten as-is.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

if [[ -z "${BASH_VERSINFO:-}" ]] || [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  echo "Error: This script requires Bash 4+ (associative arrays are used). Current bash: ${BASH_VERSION:-unknown}" >&2
  exit 1
fi

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Where to read scripts from:
# - zip: download ZIP_URL (no git required)
# - local: use REPO_DIR
SOURCE_MODE="zip"

# GitHub ZIP URL (main branch by default). You can also point this at a tagged release ZIP.
ZIP_URL="https://github.com/evenwebb/unraid-user-scripts/archive/refs/heads/main.zip"

# Local checkout of this repo (only used when SOURCE_MODE="local")
REPO_DIR="/boot/config/unraid-user-scripts"

# Unraid User Scripts plugin scripts directory
DEST_DIR="/boot/config/plugins/user.scripts/scripts"

# 1 = fetch a fresh ZIP each run (zip mode), 0 = reuse cached ZIP (if present)
FETCH_UPDATES="1"

# 1 = dry run (no changes), 0 = apply
DRY_RUN="1"

# Backups of updated destination scripts
BACKUP_DIR="/boot/config/plugins/user.scripts/backups"

# Working directory for downloads/extraction (must be writable)
WORK_DIR="/tmp/user-scripts-updater"

# Download timeouts for ZIP fetch (seconds)
DOWNLOAD_CONNECT_TIMEOUT="15"
DOWNLOAD_MAX_TIME="300"

# 1 = clear cached ZIP and extraction before running
# Use this if GitHub has updated but you keep getting "not modified" or stale results.
CLEAR_CACHE="0"

# 1 = install folders that do not already exist in DEST_DIR
# 0 = update only folders that already exist (recommended default)
INSTALL_MISSING="0"

###############################################################################

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $*"
}

log_err() {
  echo "[$(timestamp)] ERROR: $*" >&2
}

log_stderr() {
  # Use this for messages inside functions that return data via stdout.
  echo "[$(timestamp)] $*" >&2
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    log_err "Missing required command: $cmd"
    exit 1
  }
}

files_equal() {
  local a="$1"
  local b="$2"
  [[ -f "$a" && -f "$b" ]] || return 1
  cmp -s "$a" "$b"
}

download_file() {
  local url="$1"
  local out="$2"

  if command -v curl >/dev/null 2>&1; then
    # -R: set local mtime from remote Last-Modified (enables effective -z later)
    curl -fsSL -R --connect-timeout "$DOWNLOAD_CONNECT_TIMEOUT" -m "$DOWNLOAD_MAX_TIME" "$url" -o "$out"
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return $?
  fi

  log_err "Need curl or wget to download: $url"
  return 1
}

download_file_if_modified() {
  # Downloads url -> out only if modified since existing out (curl only).
  # Returns:
  #   0 = downloaded (new content)
  #   2 = not modified (HTTP 304)
  #   1 = error
  local url="$1"
  local out="$2"

  if ! command -v curl >/dev/null 2>&1; then
    # Fallback: always download (no conditional support).
    download_file "$url" "$out"
    return $?
  fi

  if [[ -f "$out" ]]; then
    # -z <file>: If-Modified-Since using file mtime
    # -R: write remote Last-Modified as local mtime (for next run)
    local http
    http="$(curl -sS -L -R --connect-timeout "$DOWNLOAD_CONNECT_TIMEOUT" -m "$DOWNLOAD_MAX_TIME" -z "$out" -o "$out.tmp" -w '%{http_code}' "$url" 2>/dev/null || true)"
    if [[ "$http" == "304" ]]; then
      rm -f "$out.tmp" 2>/dev/null || true
      return 2
    fi
    if [[ "$http" == "200" ]]; then
      mv "$out.tmp" "$out"
      return 0
    fi
    rm -f "$out.tmp" 2>/dev/null || true
    log_err "Download failed (HTTP $http): $url"
    return 1
  fi

  download_file "$url" "$out"
  return $?
}

ensure_work_dir() {
  if [[ -z "$WORK_DIR" ]]; then
    log_err "WORK_DIR is empty"
    return 1
  fi
  mkdir -p "$WORK_DIR" 2>/dev/null || true
  if [[ ! -d "$WORK_DIR" ]]; then
    log_err "WORK_DIR not usable: $WORK_DIR"
    return 1
  fi
}

clear_cache_if_requested() {
  [[ "$CLEAR_CACHE" != "1" ]] && return 0
  ensure_work_dir || return 1
  log_stderr "Clearing cache in WORK_DIR: $WORK_DIR"
  rm -rf "$WORK_DIR/extracted" 2>/dev/null || true
  rm -f "$WORK_DIR/unraid-user-scripts.zip" 2>/dev/null || true
  return 0
}

prepare_source_folders() {
  # Echoes the source folder path to stdout.
  if [[ "$SOURCE_MODE" == "local" ]]; then
    if [[ -z "$REPO_DIR" || ! -d "$REPO_DIR" ]]; then
      log_err "REPO_DIR not found: $REPO_DIR"
      return 1
    fi
    local src_folders="$REPO_DIR/user-scripts-folders"
    if [[ ! -d "$src_folders" ]]; then
      log_err "Source folders not found: $src_folders"
      return 1
    fi
    echo "$src_folders"
    return 0
  fi

  if [[ "$SOURCE_MODE" != "zip" ]]; then
    log_err "SOURCE_MODE must be 'zip' or 'local'"
    return 1
  fi

  if [[ -z "$ZIP_URL" ]]; then
    log_err "ZIP_URL is empty"
    return 1
  fi

  ensure_work_dir || return 1
  clear_cache_if_requested || return 1
  local zip_path="$WORK_DIR/unraid-user-scripts.zip"
  local extract_dir="$WORK_DIR/extracted"

  if [[ "$FETCH_UPDATES" == "1" || ! -f "$zip_path" ]]; then
    log_stderr "Downloading ZIP: $ZIP_URL"
    if [[ "$DRY_RUN" == "1" ]]; then
      log_stderr "DRY_RUN: downloading/extracting is allowed (no destination writes)."
    fi
    local dl_rc=0
    download_file_if_modified "$ZIP_URL" "$zip_path" || dl_rc=$?
    if [[ $dl_rc -eq 1 ]]; then
      return 1
    fi
    if [[ $dl_rc -eq 0 ]]; then
      log_stderr "ZIP updated."
      rm -rf "$extract_dir" 2>/dev/null || true
    else
      log_stderr "ZIP not modified (no download)."
    fi
  else
    log_stderr "Using cached ZIP: $zip_path"
  fi

  # Always extract so DRY_RUN can still produce a real preview.
  require_cmd unzip
  rm -rf "$extract_dir" 2>/dev/null || true
  mkdir -p "$extract_dir" 2>/dev/null || true
  unzip -q "$zip_path" -d "$extract_dir" || {
    log_err "Failed to unzip: $zip_path"
    return 1
  }
  # ZIP contains a single top-level folder.
  local top_dir
  top_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
  if [[ -z "$top_dir" ]]; then
    log_err "Unexpected ZIP layout (no top dir) in $extract_dir"
    return 1
  fi
  local src_folders="$top_dir/user-scripts-folders"
  if [[ ! -d "$src_folders" ]]; then
    log_err "user-scripts-folders not found in ZIP: $src_folders"
    return 1
  fi
  echo "$src_folders"
  return 0
}

get_config_range() {
  # Prints: "<start_line> <end_line>" or nothing if marker not found.
  local file="$1"
  awk '
    BEGIN { start=0; end=0 }
    start==0 && $0 ~ /^#[[:space:]]*EDIT[[:space:]]+FOR[[:space:]]+YOUR[[:space:]]+SETUP[[:space:]]*$/ { start=NR+1; next }
    start>0 && end==0 && $0 ~ /^[A-Za-z_][A-Za-z0-9_]*\\(\\)[[:space:]]*\\{/ { end=NR-1; print start, end; exit }
    END { if (start>0 && end==0) { end=NR; print start, end } }
  ' "$file"
}

extract_config_block() {
  local file="$1"
  local start end
  read -r start end < <(get_config_range "$file" || true)
  if [[ -z "${start:-}" || -z "${end:-}" ]]; then
    return 1
  fi
  sed -n "${start},${end}p" "$file"
}

line_is_assignment() {
  local line="$1"
  [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)= ]]
}

assignment_key() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"
  printf '%s' "${line%%=*}"
}

line_starts_multiline_array() {
  # True when the line looks like: KEY=(   and does not close on the same line.
  # We intentionally keep this conservative.
  local line="$1"
  local re='^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\\('
  if [[ ! "$line" =~ $re ]]; then
    return 1
  fi
  # If a closing ")" appears later on the same line, treat as single-line.
  [[ "$line" == *")"* ]] && return 1
  return 0
}

line_is_array_close() {
  # Matches a bare closing paren line, optionally with trailing comment.
  local line="$1"
  local re='^[[:space:]]*[)][[:space:]]*(#.*)?$'
  [[ "$line" =~ $re ]]
}

merge_config_blocks() {
  # Usage: merge_config_blocks <dest_existing_script> <src_new_script> <out_path>
  local dest_existing="$1"
  local src_new="$2"
  local out="$3"

  local start end
  if ! read -r start end < <(get_config_range "$src_new"); then
    cp "$src_new" "$out"
    return 0
  fi

  if [[ ! -f "$dest_existing" ]]; then
    cp "$src_new" "$out"
    return 0
  fi

  local src_block dest_block
  src_block="$(extract_config_block "$src_new" || true)"
  dest_block="$(extract_config_block "$dest_existing" || true)"

  # If either side lacks a parseable config block, fall back to full overwrite.
  if [[ -z "$src_block" || -z "$dest_block" ]]; then
    cp "$src_new" "$out"
    return 0
  fi

  declare -A dest_by_key=()
  declare -A used=()
  local line key

  # Build a map of key -> full assignment block (supports multi-line arrays).
  while IFS= read -r line; do
    if line_is_assignment "$line"; then
      key="$(assignment_key "$line")"
      if line_starts_multiline_array "$line"; then
        local block="$line"$'\n'
        while IFS= read -r line; do
          block+="$line"$'\n'
          line_is_array_close "$line" && break
        done
        dest_by_key["$key"]="$block"
      else
        dest_by_key["$key"]="$line"
      fi
    fi
  done <<<"$dest_block"

  local merged_block=""

  # Rebuild config block using upstream structure, but inject dest values by key.
  while IFS= read -r line; do
    if line_is_assignment "$line"; then
      key="$(assignment_key "$line")"

      # Consume the full upstream assignment block if this is a multi-line array.
      local src_block_text="$line"
      if line_starts_multiline_array "$line"; then
        src_block_text+=$'\n'
        while IFS= read -r line; do
          src_block_text+="$line"$'\n'
          line_is_array_close "$line" && break
        done
      fi

      if [[ -n "${dest_by_key[$key]:-}" ]]; then
        merged_block+="${dest_by_key[$key]}"$'\n'
        used["$key"]=1
      else
        # Keep the upstream assignment block.
        if [[ "$src_block_text" == *$'\n' ]]; then
          merged_block+="$src_block_text"
        else
          merged_block+="$src_block_text"$'\n'
        fi
      fi
    else
      merged_block+="$line"$'\n'
    fi
  done <<<"$src_block"

  # Append local-only variables that no longer exist upstream (kept for safety).
  local orphan_count=0
  for key in "${!dest_by_key[@]}"; do
    if [[ -z "${used[$key]:-}" ]]; then
      orphan_count=$((orphan_count + 1))
    fi
  done
  if [[ $orphan_count -gt 0 ]]; then
    merged_block+=$'\n'
    merged_block+="# NOTE: The following local-only variables were preserved but are not present upstream:"$'\n'
    for key in "${!dest_by_key[@]}"; do
      if [[ -z "${used[$key]:-}" ]]; then
        merged_block+="${dest_by_key[$key]}"$'\n'
      fi
    done
  fi

  # Rebuild full script: head + merged_block + tail
  local tmp
  tmp="$(mktemp)"
  head -n $((start - 1)) "$src_new" > "$tmp"
  printf '%s' "$merged_block" >> "$tmp"
  tail -n +"$((end + 1))" "$src_new" >> "$tmp"
  mv "$tmp" "$out"
}

backup_file() {
  local src="$1"
  local rel="$2"
  local base
  base="$(basename "$src")"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local out_dir="$BACKUP_DIR/$rel"
  mkdir -p "$out_dir" 2>/dev/null || true
  cp "$src" "$out_dir/$base.$stamp.bak"
}

sync_one_folder() {
  local src_folder="$1"
  local dest_folder="$2"

  local src_script="$src_folder/script"
  local src_name="$src_folder/name"
  local src_desc="$src_folder/description"

  local dest_script="$dest_folder/script"
  local dest_name="$dest_folder/name"
  local dest_desc="$dest_folder/description"

  if [[ ! -f "$src_script" ]]; then
    log_err "Missing source script: $src_script"
    return 1
  fi

  if [[ ! -d "$dest_folder" ]]; then
    if [[ "$INSTALL_MISSING" != "1" ]]; then
      log "Skipping missing folder (not installed): $(basename "$dest_folder")"
      return 2
    fi
    log "Installing new folder: $(basename "$dest_folder")"
    if [[ "$DRY_RUN" == "0" ]]; then
      mkdir -p "$dest_folder"
      cp "$src_script" "$dest_script"
      [[ -f "$src_name" ]] && cp "$src_name" "$dest_name" || true
      [[ -f "$src_desc" ]] && cp "$src_desc" "$dest_desc" || true
    fi
    return 0
  fi

  local merged
  merged="$(mktemp)"
  if [[ -f "$dest_script" ]]; then
    merge_config_blocks "$dest_script" "$src_script" "$merged"
  else
    cp "$src_script" "$merged"
  fi

  local changed=0
  if [[ ! -f "$dest_script" ]] || ! files_equal "$merged" "$dest_script"; then
    changed=1
  fi
  if [[ -f "$src_name" ]]; then
    if [[ ! -f "$dest_name" ]] || ! files_equal "$src_name" "$dest_name"; then
      changed=1
    fi
  fi
  if [[ -f "$src_desc" ]]; then
    if [[ ! -f "$dest_desc" ]] || ! files_equal "$src_desc" "$dest_desc"; then
      changed=1
    fi
  fi

  if [[ $changed -eq 0 ]]; then
    rm -f "$merged"
    log "No changes: $(basename "$dest_folder")"
    return 2
  fi

  log "Updating folder: $(basename "$dest_folder")"

  if [[ "$DRY_RUN" == "0" && -f "$dest_script" ]]; then
    backup_file "$dest_script" "$(basename "$dest_folder")"
  fi

  if [[ "$DRY_RUN" == "0" ]]; then
    cp "$merged" "$dest_script"
    [[ -f "$src_name" ]] && cp "$src_name" "$dest_name" || true
    [[ -f "$src_desc" ]] && cp "$src_desc" "$dest_desc" || true
  fi
  rm -f "$merged"
  return 0
}

main() {
  require_cmd awk
  require_cmd sed
  require_cmd head
  require_cmd tail
  require_cmd mktemp
  require_cmd cp
  require_cmd mv
  require_cmd cmp
  require_cmd find
  require_cmd sort

  if [[ -z "$DEST_DIR" ]]; then
    log_err "DEST_DIR is empty"
    return 1
  fi

  if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
    log_err "DRY_RUN must be 0 or 1"
    return 1
  fi
  if [[ "$FETCH_UPDATES" != "0" && "$FETCH_UPDATES" != "1" ]]; then
    log_err "FETCH_UPDATES must be 0 or 1"
    return 1
  fi
  if [[ "$CLEAR_CACHE" != "0" && "$CLEAR_CACHE" != "1" ]]; then
    log_err "CLEAR_CACHE must be 0 or 1"
    return 1
  fi
  if [[ "$INSTALL_MISSING" != "0" && "$INSTALL_MISSING" != "1" ]]; then
    log_err "INSTALL_MISSING must be 0 or 1"
    return 1
  fi

  local src_folders
  # prepare_source_folders returns the source path on stdout. Harden against any
  # unexpected extra output by taking the last line only.
  src_folders="$(prepare_source_folders | tail -n 1)" || return 1
  if [[ -z "$src_folders" || ! -d "$src_folders" ]]; then
    log_err "Invalid source folder path: $src_folders"
    return 1
  fi

  if [[ "$DRY_RUN" == "0" ]]; then
    mkdir -p "$DEST_DIR" "$BACKUP_DIR" 2>/dev/null || true
  fi

  log "Syncing User Scripts folders"
  log "Source: $src_folders"
  log "Dest: $DEST_DIR"
  log "DryRun: $DRY_RUN"

  local src_folder folder_name dest_folder
  local updated=0 skipped=0 fail=0
  while IFS= read -r src_folder; do
    folder_name="$(basename "$src_folder")"
    dest_folder="$DEST_DIR/$folder_name"
    sync_one_folder "$src_folder" "$dest_folder"
    case $? in
      0) updated=$((updated + 1)) ;;
      2) skipped=$((skipped + 1)) ;;
      *) fail=$((fail + 1)) ;;
    esac
  done < <(find "$src_folders" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  log "Done. Updated: ${updated:-0}, Skipped: ${skipped:-0}, Failed: ${fail:-0}"
  if [[ "${fail:-0}" -gt 0 ]]; then
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

