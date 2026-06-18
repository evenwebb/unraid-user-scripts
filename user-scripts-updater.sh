#!/bin/bash
#
# user-scripts-updater.sh
# Update User Scripts plugin folders from GitHub while keeping your config edits.
#
# Description:
#   Downloads this repo (or uses a local copy), updates installed script folders, and merges EDIT FOR YOUR SETUP blocks.
#   On each live run, checks whether this updater script is current; if not, updates itself and re-runs
#   with the new version before syncing other scripts (so new merge/sync logic is always used).
#
# Usage:
#   Run from User Scripts (foreground first, then schedule).
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only (default), 0 = apply updates
#
# Configuration (edit script variables below):
#   - SOURCE_MODE: zip or local
#   - ZIP_URL / REPO_DIR / DEST_DIR
#   - FETCH_UPDATES / CLEAR_CACHE / INSTALL_MISSING
#   - DRY_RUN / BACKUP_DIR / WORK_DIR
#   - RESET_CONFIG / CONFIG_CONFLICT_MODE / SHOW_CONFIG_DIFF
#   - LOCK_FILE / BACKUP_KEEP_COUNT
#   - INCLUDE_FOLDERS / EXCLUDE_FOLDERS
#   - DOWNLOAD_CONNECT_TIMEOUT / DOWNLOAD_MAX_TIME
#
# Note: Progress and errors print to stdout; Unraid User Scripts shows that in the run window. Optional LOG_FILE also appends a copy to disk.
#
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0

set -u
set -o pipefail

if [[ -z "${BASH_VERSINFO:-}" ]] || [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]] || { [[ "${BASH_VERSINFO[0]:-0}" -eq 4 ]] && [[ "${BASH_VERSINFO[1]:-0}" -lt 3 ]]; }; then
  _ui_msg="Error: This script requires Bash 4.3+ (declare -n is used). Current bash: ${BASH_VERSION:-unknown}"
  echo "$_ui_msg"
  echo "$_ui_msg" >&2
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

# 1 = preview only (no changes), 0 = apply updates
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

# 1 = reset local config to upstream defaults (no config merge)
# 0 = preserve local config values by merging (recommended default)
RESET_CONFIG="0"

# How to resolve conflicts when a config variable exists locally and upstream:
# "keep-local"  - your local value wins (default, safest)
# "use-upstream" - upstream default overwrites your local value when they differ
CONFIG_CONFLICT_MODE="keep-local"

# 1 = show a diff of config changes (new/removed/changed vars) during merge
SHOW_CONFIG_DIFF="1"

# Selective update: only update folders matching these names (empty = all)
INCLUDE_FOLDERS=()

# Selective update: skip these folder names (empty = none excluded)
EXCLUDE_FOLDERS=()

# Lock file to prevent concurrent updater runs (empty = no lock)
LOCK_FILE="/tmp/user-scripts-updater.lock"

# Keep at most N timestamped backups per script folder (0 = unlimited)
BACKUP_KEEP_COUNT="20"

###############################################################################

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  local msg="[$(timestamp)] $*"
  echo "$msg"
}

log_err() {
  local msg="[$(timestamp)] ERROR: $*"
  echo "$msg"
}

log_stderr() {
  # Use this for messages inside functions that return data via stdout.
  echo "[$(timestamp)] $*" >&2
}

_friendly_curl_err() {
  local msg="$1"
  msg="${msg#curl: }"
  if [[ "$msg" == *"Could not resolve host"* ]]; then
    echo "The server name could not be found - check ZIP_URL in this script."
  elif [[ "$msg" == *"Connection refused"* ]] || [[ "$msg" == *"Failed to connect"* ]]; then
    echo "Could not connect - check ZIP_URL and your network."
  elif [[ "$msg" == *"timed out"* ]] || [[ "$msg" == *"Timeout"* ]]; then
    echo "The download timed out - increase DOWNLOAD_MAX_TIME in this script or check your network."
  elif [[ "$msg" == *"404"* ]]; then
    echo "The file was not found at that URL - check ZIP_URL in this script."
  else
    echo "$msg"
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    log_err "Missing required command: $cmd"
    exit 1
  }
}

# Compare text files as User Scripts would see them: ignore CR (CRLF on flash),
# and normalize missing final newlines so merge output matches on-disk copies.
_normalize_for_compare() {
  local clean
  clean="$(mktemp)"
  tr -d '\r' < "$1" > "$clean"
  awk '{ print $0 }' "$clean"
  rm -f "$clean"
}

files_equal() {
  local a="$1"
  local b="$2"
  [[ -f "$a" && -f "$b" ]] || return 1
  cmp -s <(_normalize_for_compare "$a") <(_normalize_for_compare "$b")
}

# True when the editable block has the same line span on disk and in the ZIP,
# and everything outside that block matches. Then only EDIT-block settings differ
# (or formatting inside the block). Used to avoid rewriting the User Scripts
# Updater script on every run after changing DRY_RUN, paths, etc.
upstream_heads_and_tails_match() {
  local dest_script="$1"
  local src_script="$2"
  local s_src e_src s_dest e_dest
  local hf1 hf2 tf1 tf2 clean_dest clean_src rc=0
  read -r s_src e_src < <(get_config_range "$src_script") || return 1
  read -r s_dest e_dest < <(get_config_range "$dest_script") || return 1
  [[ "$s_src" == "$s_dest" && "$e_src" == "$e_dest" ]] || return 1

  # Normalize to temp files first so head/tail never SIGPIPE a streaming tr.
  hf1="$(mktemp)"
  hf2="$(mktemp)"
  tf1="$(mktemp)"
  tf2="$(mktemp)"
  clean_dest="$(mktemp)"
  clean_src="$(mktemp)"
  tr -d '\r' < "$dest_script" > "$clean_dest"
  tr -d '\r' < "$src_script" > "$clean_src"
  head -n $((s_src - 1)) "$clean_dest" > "$hf1"
  head -n $((s_src - 1)) "$clean_src" > "$hf2"
  tail -n +$((e_src + 1)) "$clean_dest" > "$tf1"
  tail -n +$((e_src + 1)) "$clean_src" > "$tf2"

  files_equal "$hf1" "$hf2" && files_equal "$tf1" "$tf2" || rc=1
  rm -f "$hf1" "$hf2" "$tf1" "$tf2" "$clean_dest" "$clean_src"
  return "$rc"
}

download_file() {
  local url="$1"
  local out="$2"
  local curl_err

  if command -v curl >/dev/null 2>&1; then
    curl_err=$(mktemp) || { log_err "Could not create temp file for download."; return 1; }
    if curl -fsSL -R --connect-timeout "$DOWNLOAD_CONNECT_TIMEOUT" -m "$DOWNLOAD_MAX_TIME" "$url" -o "$out" 2>"$curl_err"; then
      rm -f "$curl_err"
      return 0
    fi
    log_err "Could not download from ${url}. $(_friendly_curl_err "$(tr '\n' ' ' <"$curl_err")") Check ZIP_URL in this script."
    rm -f "$curl_err"
    return 1
  fi
  if command -v wget >/dev/null 2>&1; then
    if wget -qO "$out" "$url"; then
      return 0
    fi
    log_err "Could not download from ${url} using wget. Check ZIP_URL and network."
    return 1
  fi

  log_err "Need curl or wget to download updates. Check ZIP_URL in this script: $url"
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
    if [[ "$http" == "401" || "$http" == "403" ]]; then
      log_err "Download was rejected (HTTP $http). Check ZIP_URL in this script."
    elif [[ "$http" == "404" ]]; then
      log_err "Download URL not found (HTTP 404). Check ZIP_URL in this script: $url"
    else
      log_err "Download failed (HTTP ${http:-unknown}). Check ZIP_URL and network: $url"
    fi
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
  if [[ "$SOURCE_MODE" != "zip" && "$SOURCE_MODE" != "local" ]]; then
    log_err "SOURCE_MODE must be 'zip' or 'local' (you entered: ${SOURCE_MODE}). Edit the settings at the top of this script."
    return 1
  fi
  if [[ "$SOURCE_MODE" == "local" ]]; then
    if [[ -z "$REPO_DIR" || ! -d "$REPO_DIR" ]]; then
      log_err "REPO_DIR not found: $REPO_DIR. Check REPO_DIR in this script."
      return 1
    fi
    local src_folders="$REPO_DIR/user-scripts-folders"
    if [[ ! -d "$src_folders" ]]; then
      log_err "Source folders not found: $src_folders. Check REPO_DIR in this script."
      return 1
    fi
    echo "$src_folders"
    return 0
  fi

  if [[ -z "$ZIP_URL" ]]; then
    log_err "ZIP_URL is empty. Set ZIP_URL in this script."
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

  # Compute ZIP fingerprint to skip redundant extraction
  local zip_fingerprint
  zip_fingerprint=$(md5sum "$zip_path" 2>/dev/null | awk '{print $1}' || true)
  local fingerprint_file="$extract_dir/.zip-fingerprint"

  if [[ -d "$extract_dir" && -f "$fingerprint_file" && -n "$zip_fingerprint" ]]; then
    local stored_fp
    stored_fp=$(tr -d '\r\n' < "$fingerprint_file" 2>/dev/null || true)
    if [[ "$zip_fingerprint" == "$stored_fp" ]]; then
      log_stderr "ZIP fingerprint unchanged; reusing cached extraction."
    else
      log_stderr "ZIP fingerprint changed; re-extracting."
      rm -rf "$extract_dir" 2>/dev/null || true
      mkdir -p "$extract_dir" 2>/dev/null || true
      unzip -q "$zip_path" -d "$extract_dir" || {
        log_err "Failed to unzip: $zip_path"
        return 1
      }
      printf '%s\n' "$zip_fingerprint" > "$fingerprint_file"
    fi
  else
    rm -rf "$extract_dir" 2>/dev/null || true
    mkdir -p "$extract_dir" 2>/dev/null || true
    unzip -q "$zip_path" -d "$extract_dir" || {
      log_err "Failed to unzip: $zip_path"
      return 1
    }
    if [[ -n "$zip_fingerprint" ]]; then
      printf '%s\n' "$zip_fingerprint" > "$fingerprint_file"
    fi
  fi
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
  # Prints: "<start_line> <end_line>" - content between EDIT markers (####### blocks).
  local file="$1"
  local line lineno=0 phase=0 start=0 end=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    lineno=$((lineno + 1))
    case $phase in
      0)
        [[ "$line" =~ ^#[[:space:]]*EDIT[[:space:]]+FOR[[:space:]]+YOUR[[:space:]]+SETUP ]] && phase=1
        ;;
      1)
        [[ "$line" =~ ^#[[:space:]]*#{5,}[[:space:]]*$ ]] && phase=2
        ;;
      2)
        if [[ $start -eq 0 ]]; then
          [[ "$line" =~ ^[[:space:]]*$ ]] && continue
          start=$lineno
        fi
        if [[ "$line" =~ ^#[[:space:]]*#{5,}[[:space:]]*$ ]]; then
          end=$((lineno - 1))
          while [[ $end -ge $start ]]; do
            line=$(sed -n "${end}p" "$file" | tr -d '\r')
            [[ "$line" =~ ^[[:space:]]*$ ]] && end=$((end - 1)) || break
          done
          [[ $start -le $end ]] && printf '%s %s\n' "$start" "$end"
          return 0
        fi
        ;;
    esac
  done < "$file"
}

extract_config_block() {
  local file="$1"
  local start end
  read -r start end < <(get_config_range "$file" || true)
  if [[ -z "${start:-}" || -z "${end:-}" ]]; then
    return 1
  fi
  local clean
  clean="$(mktemp)"
  tr -d '\r' < "$file" > "$clean"
  sed -n "${start},${end}p" "$clean"
  rm -f "$clean"
}

line_is_assignment() {
  local line="$1"
  [[ "$line" =~ ^[[:space:]]*# ]] && return 1
  [[ "$line" =~ ^[[:space:]]*$ ]] && return 1
  # Allow spaces around = (e.g. VAR = "x"). Optional export prefix.
  local ere='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*='
  [[ "$line" =~ $ere ]]
}

assignment_key() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"
  if [[ "$line" =~ ^export[[:space:]]+ ]]; then
    line="${line#export}"
    line="${line#"${line%%[![:space:]]*}"}"
  fi
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*= ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "${line%%=*}"
  fi
}

line_starts_multiline_array() {
  # True when the line looks like: [export ]KEY=(   and does not close on the same line.
  # We intentionally keep this conservative.
  local line="$1"
  local re='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=\('
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

# Populate associative array VAR_NAME -> assignment text from an EDIT-region block string.
# First occurrence wins per variable name inside the EDIT block so edge-case duplicate
# keys do not silently shadow earlier saved assignments.
build_dest_assignment_map() {
  local -n dest_by_key_ref="$1"
  local block_text="$2"
  local line key
  while IFS= read -r line; do
    if line_is_assignment "$line"; then
      key="$(assignment_key "$line")"
      if [[ -n "${dest_by_key_ref[$key]:-}" ]]; then
        continue
      fi
      if line_starts_multiline_array "$line"; then
        local mblock="$line"$'\n'
        while IFS= read -r line; do
          mblock+="$line"$'\n'
          line_is_array_close "$line" && break
        done
        dest_by_key_ref["$key"]="$mblock"
      else
        dest_by_key_ref["$key"]="$line"
      fi
    fi
  done <<<"$block_text"
}

config_block_signature() {
  # Prints a normalized signature of the editable config block:
  # - assignment values are discarded, only variable keys remain
  # - comments/blank lines are preserved so upstream text/layout changes are detected
  local file="$1"
  local block_text line key
  block_text="$(extract_config_block "$file" || true)"
  [[ -z "$block_text" ]] && return 1

  while IFS= read -r line; do
    if line_is_assignment "$line"; then
      key="$(assignment_key "$line")"
      printf 'A:%s\n' "$key"
      if line_starts_multiline_array "$line"; then
        while IFS= read -r line; do
          line_is_array_close "$line" && break
        done
      fi
    else
      printf 'T:%s\n' "$line"
    fi
  done <<<"$block_text"
}

config_block_text_changed() {
  local dest_script="$1"
  local src_script="$2"
  local dest_sig src_sig
  dest_sig="$(config_block_signature "$dest_script" || true)"
  src_sig="$(config_block_signature "$src_script" || true)"
  [[ -z "$dest_sig" || -z "$src_sig" ]] && return 1
  [[ "$dest_sig" != "$src_sig" ]]
}

log_config_merge_diff() {
  local dest_script="$1" src_script="$2" folder_label="$3"
  [[ "$SHOW_CONFIG_DIFF" == "1" ]] || return 0
  local dest_block src_block
  dest_block="$(extract_config_block "$dest_script" || true)"
  src_block="$(extract_config_block "$src_script" || true)"
  [[ -z "$dest_block" || -z "$src_block" ]] && return 0
  declare -A dest_map=()
  build_dest_assignment_map dest_map "$dest_block"
  local line key src_val dest_val
  while IFS= read -r line; do
    line_is_assignment "$line" || continue
    key="$(assignment_key "$line")"
    src_val="$line"
    if line_starts_multiline_array "$line"; then
      src_val="$line"$'\n'
      while IFS= read -r line; do
        src_val+="$line"$'\n'
        line_is_array_close "$line" && break
      done
    fi
    dest_val="${dest_map[$key]:-}"
    if [[ -z "$dest_val" ]]; then
      log "Config merge ($folder_label): + $key (new upstream variable)"
    elif [[ "$dest_val" != "$src_val" && "$dest_val" != "${src_val%$'\n'}" ]]; then
      log "Config merge ($folder_label): keeping local $key (upstream default differs)"
    fi
  done <<<"$src_block"
}

merge_config_blocks() {
  # Usage: merge_config_blocks <dest_existing_script> <src_new_script> <out_path>
  #
  # Sets MERGE_KEPT / MERGE_NEW / MERGE_ORPHAN counts for logging.
  MERGE_KEPT=0
  MERGE_NEW=0
  MERGE_ORPHAN=0
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

  if [[ -z "$src_block" ]]; then
    cp "$src_new" "$out"
    return 0
  fi

  if [[ -z "$dest_block" ]]; then
    cp "$src_new" "$out"
    return 0
  fi

  declare -A dest_by_key=()
  declare -A used=()
  local line key

  build_dest_assignment_map dest_by_key "$dest_block"

  local merged_block=""

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
        MERGE_KEPT=$((MERGE_KEPT + 1))
        local chosen="${dest_by_key[$key]}"
        if [[ "$CONFIG_CONFLICT_MODE" == "use-upstream" ]]; then
          chosen="$src_block_text"
        fi
        merged_block+="$chosen"
        [[ "$chosen" == *$'\n' ]] || merged_block+=$'\n'
        used["$key"]=1
      else
        MERGE_NEW=$((MERGE_NEW + 1))
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
  MERGE_ORPHAN=$orphan_count
  if [[ $orphan_count -gt 0 ]]; then
    merged_block+=$'\n'
    merged_block+="# NOTE: The following local-only variables were preserved but are not present upstream:"$'\n'
    # Deterministic order (bash associative key order is undefined).
    local orphan_key
    while IFS= read -r orphan_key; do
      [[ -z "$orphan_key" ]] && continue
      if [[ -z "${used[$orphan_key]:-}" ]]; then
        merged_block+="${dest_by_key[$orphan_key]}"
        [[ "${dest_by_key[$orphan_key]}" == *$'\n' ]] || merged_block+=$'\n'
      fi
    done < <(printf '%s\n' "${!dest_by_key[@]}" | LC_ALL=C sort -u)
  fi

  # Rebuild full script: head + merged_block + tail (LF-only; tr strips CR).
  # Normalize once to a temp file so head/tail do not SIGPIPE a streaming tr.
  local tmp clean_src
  tmp="$(mktemp)"
  clean_src="$(mktemp)"
  tr -d '\r' < "$src_new" > "$clean_src"
  head -n $((start - 1)) "$clean_src" > "$tmp"
  printf '%s' "$merged_block" >> "$tmp"
  tail -n +"$((end + 1))" "$clean_src" >> "$tmp"
  rm -f "$clean_src"
  mv "$tmp" "$out"
}

backup_file() {
  local src="$1"
  local rel="$2"
  local base stamp out_dir
  base="$(basename "$src")"
  stamp="$(date +%Y%m%d-%H%M%S)"
  out_dir="$BACKUP_DIR/$rel"
  mkdir -p "$out_dir" 2>/dev/null || true
  cp "$src" "$out_dir/$base.$stamp.bak"
  if [[ "$BACKUP_KEEP_COUNT" =~ ^[0-9]+$ ]] && [[ "$BACKUP_KEEP_COUNT" -gt 0 ]]; then
    local old_backups count
    old_backups=$(find "$out_dir" -maxdepth 1 -name "$base.*.bak" -type f 2>/dev/null | sort -r)
    count=0
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      count=$((count + 1))
      [[ $count -gt $BACKUP_KEEP_COUNT ]] && rm -f "$f"
    done <<< "$old_backups"
  fi
}

script_is_user_scripts_updater() {
  local f="$1"
  head -n 5 "$f" 2>/dev/null | grep -q '^# user-scripts-updater\.sh'
}

atomic_replace_file() {
  local src="$1"
  local dest="$2"
  local dest_dir dest_base tmp
  dest_dir="$(dirname "$dest")"
  dest_base="$(basename "$dest")"
  mkdir -p "$dest_dir" 2>/dev/null || true
  tmp="$(mktemp "$dest_dir/.${dest_base}.tmp.XXXXXX")" || return 1
  cp "$src" "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$dest"
}

validate_bash_script() {
  local script_path="$1"
  local label="${2:-script}"
  if ! bash -n "$script_path" >/dev/null 2>&1; then
    log_err "Syntax validation failed for $label: $script_path"
    bash -n "$script_path" 2>&1 | while IFS= read -r line; do
      log_stderr "  $line"
    done
    return 1
  fi
  return 0
}

merge_settings_note() {
  [[ "${MERGE_KEPT:-0}" -gt 0 || "${MERGE_NEW:-0}" -gt 0 || "${MERGE_ORPHAN:-0}" -gt 0 ]] || return 0
  local note="config: ${MERGE_KEPT} kept"
  [[ "${MERGE_NEW:-0}" -gt 0 ]] && note+=", ${MERGE_NEW} new"
  [[ "${MERGE_ORPHAN:-0}" -gt 0 ]] && note+=", ${MERGE_ORPHAN} local-only"
  printf '%s' "$note"
}

list_to_csv() {
  local _out="" _item
  for _item in "$@"; do
    [[ -z "$_item" ]] && continue
    [[ -n "$_out" ]] && _out+=", "
    _out+="$_item"
  done
  printf '%s' "$_out"
}

# Return path to the User Scripts Updater folder under a user-scripts-folders root.
find_updater_src_folder() {
  local src_root="$1"
  local d script
  for d in "$src_root"/*; do
    [[ -d "$d" ]] || continue
    script="$d/script"
    if [[ -f "$script" ]] && script_is_user_scripts_updater "$script"; then
      printf '%s' "$d"
      return 0
    fi
  done
  return 1
}

# True when script code outside the EDIT block differs between dest and src.
upstream_code_differs() {
  local dest_script="$1" src_script="$2"
  ! upstream_heads_and_tails_match "$dest_script" "$src_script"
}

self_update_and_maybe_reexec() {
  local src_folders="$1"
  local src_folder dest_folder dest_script src_script folder_name running_script rc

  src_folder="$(find_updater_src_folder "$src_folders")" || {
    log_err "User Scripts Updater folder not found in upstream source."
    return 1
  }
  folder_name="$(basename "$src_folder")"
  UPDATER_FOLDER_NAME="$folder_name"

  if [[ "${USER_SCRIPTS_UPDATER_REEXEC:-0}" == "1" ]]; then
    log "Continuing with updated User Scripts Updater; syncing remaining scripts."
    return 0
  fi

  dest_folder="$DEST_DIR/$folder_name"
  dest_script="$dest_folder/script"
  src_script="$src_folder/script"

  if [[ ! -f "$dest_script" ]]; then
    log "User Scripts Updater not installed on flash yet; self-update skipped (install it first or set INSTALL_MISSING=1)."
    return 0
  fi

  running_script="${BASH_SOURCE[0]:-$0}"

  log "Checking User Scripts Updater code on flash (your EDIT settings are always preserved)..."

  if upstream_code_differs "$dest_script" "$src_script"; then
    log "User Scripts Updater code on flash is outdated; updating before syncing other scripts..."
    sync_one_folder "$src_folder" "$dest_folder"
    rc=$?
    case "$rc" in
      0)
        if [[ "$DRY_RUN" == "1" ]]; then
          log "DRY_RUN: would re-launch updater from flash, then sync other scripts."
          return 0
        fi
        log "Re-launching from flash with updated User Scripts Updater..."
        export USER_SCRIPTS_UPDATER_REEXEC=1
        exec bash "$dest_script"
        ;;
      2)
        log_err "Updater code looked outdated but nothing changed during sync."
        return 1
        ;;
      *)
        log_err "Self-update failed for User Scripts Updater."
        return 1
        ;;
    esac
  fi

  log "User Scripts Updater code on flash is up to date."

  if script_is_user_scripts_updater "$running_script" &&
     upstream_code_differs "$running_script" "$dest_script"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY_RUN: would re-launch from flash (plugin temp copy is outdated)."
      return 0
    fi
    log "Re-launching from flash (User Scripts plugin temp copy is outdated)..."
    export USER_SCRIPTS_UPDATER_REEXEC=1
    exec bash "$dest_script"
  fi

  return 0
}

sync_one_folder() {
  local src_folder="$1"
  local dest_folder="$2"
  local folder_label merged_settings_note=""
  folder_label="$(basename "$src_folder")"

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

  validate_bash_script "$src_script" "source script $(basename "$src_folder")" || return 1

  if [[ ! -d "$dest_folder" ]]; then
    if [[ "$INSTALL_MISSING" != "1" ]]; then
      log "Skipping (not installed): $(basename "$dest_folder")"
      return 3
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
      local _install_merged
      _install_merged="$(mktemp)"
      cp "$src_script" "$_install_merged"
      validate_bash_script "$_install_merged" "would-install $folder_label" || { rm -f "$_install_merged"; return 1; }
      rm -f "$_install_merged"
      log "Would install: $folder_label"
    else
      log "Installed: $folder_label"
    fi
    if [[ "$DRY_RUN" == "0" ]]; then
      mkdir -p "$dest_folder"
      atomic_replace_file "$src_script" "$dest_script" || return 1
      [[ -f "$src_name" ]] && atomic_replace_file "$src_name" "$dest_name" || true
      [[ -f "$src_desc" ]] && atomic_replace_file "$src_desc" "$dest_desc" || true
    fi
    return 0
  fi

  local merged
  merged="$(mktemp)"
  MERGE_KEPT=0
  MERGE_NEW=0
  MERGE_ORPHAN=0
  if [[ -f "$dest_script" ]]; then
    if [[ "$RESET_CONFIG" == "1" ]]; then
      cp "$src_script" "$merged"
    else
      if files_equal "$dest_script" "$src_script"; then
        cp "$src_script" "$merged"
      else
        merge_config_blocks "$dest_script" "$src_script" "$merged"
        merged_settings_note="$(merge_settings_note)"
      fi
    fi
  else
    cp "$src_script" "$merged"
  fi

  # User Scripts Updater: after editing only EDIT-block settings, merge output can
  # still differ from the plugin-saved file (formatting). If the ZIP and flash
  # already agree outside the editable region, keep the on-disk script.
  if [[ -f "$dest_script" ]] && script_is_user_scripts_updater "$dest_script" &&
    ! files_equal "$merged" "$dest_script" &&
    upstream_heads_and_tails_match "$dest_script" "$src_script"; then
    cp "$dest_script" "$merged"
  fi

  validate_bash_script "$merged" "merged script $(basename "$dest_folder")" || {
    rm -f "$merged"
    return 1
  }

  local changed=0
  local reasons=()
  if [[ ! -f "$dest_script" ]] || ! files_equal "$merged" "$dest_script"; then
    changed=1
    reasons+=("script")
  fi
  if [[ -f "$src_name" ]]; then
    if [[ ! -f "$dest_name" ]] || ! files_equal "$src_name" "$dest_name"; then
      changed=1
      reasons+=("name")
    fi
  fi
  if [[ -f "$src_desc" ]]; then
    if [[ ! -f "$dest_desc" ]] || ! files_equal "$src_desc" "$dest_desc"; then
      changed=1
      reasons+=("description")
    fi
  fi

  if [[ $changed -eq 0 ]]; then
    rm -f "$merged"
    return 2
  fi

  log_config_merge_diff "$dest_script" "$src_script" "$folder_label"

  local reason_csv="${reasons[*]}"
  reason_csv="${reason_csv// /, }"
  [[ "$RESET_CONFIG" == "1" && " ${reasons[*]} " == *" script "* ]] && reason_csv="${reason_csv}; config reset"
  if [[ -n "$merged_settings_note" && " ${reasons[*]} " == *" script "* ]]; then
    reason_csv="${reason_csv}; ${merged_settings_note}"
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would update: $folder_label ($reason_csv)"
  else
    log "Updated: $folder_label ($reason_csv)"
  fi

  if [[ "$DRY_RUN" == "0" && -f "$dest_script" ]]; then
    backup_file "$dest_script" "$(basename "$dest_folder")"
  fi

  if [[ "$DRY_RUN" == "0" ]]; then
    atomic_replace_file "$merged" "$dest_script" || {
      rm -f "$merged"
      return 1
    }
    [[ -f "$src_name" ]] && atomic_replace_file "$src_name" "$dest_name" || true
    [[ -f "$src_desc" ]] && atomic_replace_file "$src_desc" "$dest_desc" || true
  fi
  rm -f "$merged"
  return 0
}

main() {
  require_cmd awk
  require_cmd tr
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
  if [[ "$RESET_CONFIG" != "0" && "$RESET_CONFIG" != "1" ]]; then
    log_err "RESET_CONFIG must be 0 or 1"
    return 1
  fi

  if [[ "$CONFIG_CONFLICT_MODE" != "keep-local" && "$CONFIG_CONFLICT_MODE" != "use-upstream" ]]; then
    log_err "CONFIG_CONFLICT_MODE must be 'keep-local' or 'use-upstream'"
    return 1
  fi
  if [[ "$SHOW_CONFIG_DIFF" != "0" && "$SHOW_CONFIG_DIFF" != "1" ]]; then
    log_err "SHOW_CONFIG_DIFF must be 0 or 1"
    return 1
  fi
  if [[ ! "$BACKUP_KEEP_COUNT" =~ ^[0-9]+$ ]]; then
    log_err "BACKUP_KEEP_COUNT must be a whole number (0 = unlimited)"
    return 1
  fi

  if [[ -n "$LOCK_FILE" ]]; then
    if [[ "$LOCK_FILE" == *".."* || "$LOCK_FILE" == "-"* ]]; then
      log_err "LOCK_FILE path is not allowed."
      return 1
    fi
    if command -v flock >/dev/null 2>&1; then
      exec 9>"$LOCK_FILE"
      if ! flock -n 9; then
        log_err "Another updater run is in progress (lock: $LOCK_FILE)"
        return 1
      fi
    else
      log "Note: flock not available; concurrent updater runs are not prevented."
    fi
  fi

  local src_folders
  # prepare_source_folders returns the source path on stdout. Harden against any
  # unexpected extra output by taking the last line only.
  src_folders="$(prepare_source_folders | tail -n 1)" || return 1
  if [[ -z "$src_folders" || ! -d "$src_folders" ]]; then
    log_err "Invalid source folder path: $src_folders"
    return 1
  fi

  UPDATER_FOLDER_NAME=""
  self_update_and_maybe_reexec "$src_folders" || return 1

  local src_folder folder_name dest_folder
  local updated=0 skipped=0 fail=0 unchanged=0
  local -a src_folder_list=()
  local -a updated_list=() skipped_list=() failed_list=()
  while IFS= read -r src_folder; do
    [[ -n "$src_folder" ]] && src_folder_list+=("$src_folder")
  done < <(find "$src_folders" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  if [[ "$DRY_RUN" == "0" ]]; then
    mkdir -p "$DEST_DIR" "$BACKUP_DIR" 2>/dev/null || true
  fi

  local sync_folder_count=${#src_folder_list[@]}
  [[ -n "$UPDATER_FOLDER_NAME" ]] && sync_folder_count=$((sync_folder_count - 1))
  log "Syncing ${sync_folder_count} other script folders → $DEST_DIR (dry-run: $DRY_RUN)"

  for src_folder in "${src_folder_list[@]}"; do
    folder_name="$(basename "$src_folder")"
    if [[ -n "$UPDATER_FOLDER_NAME" && "$folder_name" == "$UPDATER_FOLDER_NAME" ]]; then
      continue
    fi
    dest_folder="$DEST_DIR/$folder_name"

      # Selective update filtering
      if [[ ${#INCLUDE_FOLDERS[@]} -gt 0 ]]; then
        local _found=0 _inc
        for _inc in "${INCLUDE_FOLDERS[@]}"; do
          [[ "$folder_name" == "$_inc" ]] && { _found=1; break; }
        done
        if [[ $_found -eq 0 ]]; then
          log "Skipped (not in INCLUDE_FOLDERS): $folder_name"
          skipped_list+=("$folder_name")
          skipped=$((skipped + 1))
          continue
        fi
      fi
      local _exc
      for _exc in "${EXCLUDE_FOLDERS[@]}"; do
        if [[ "$folder_name" == "$_exc" ]]; then
          log "Skipped (in EXCLUDE_FOLDERS): $folder_name"
          skipped_list+=("$folder_name")
          skipped=$((skipped + 1))
          continue 2
        fi
      done
    sync_one_folder "$src_folder" "$dest_folder"
    case $? in
      0)
        updated=$((updated + 1))
        updated_list+=("$folder_name")
        ;;
      2)
        unchanged=$((unchanged + 1))
        ;;
      3)
        skipped=$((skipped + 1))
        skipped_list+=("$folder_name")
        ;;
      *)
        fail=$((fail + 1))
        failed_list+=("$folder_name")
        ;;
    esac
  done

  local action="Updated"
  [[ "$DRY_RUN" == "1" ]] && action="Would update"
  if [[ ${#skipped_list[@]} -gt 0 ]]; then
    log "Skipped: $(list_to_csv "${skipped_list[@]}")"
  fi
  if [[ ${#failed_list[@]} -gt 0 ]]; then
    log "Failed: $(list_to_csv "${failed_list[@]}")"
  fi

  log "Done. ${action}: ${updated:-0}, Unchanged: ${unchanged:-0}, Skipped: ${skipped:-0}, Failed: ${fail:-0}"
  if [[ "${fail:-0}" -gt 0 ]]; then
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
