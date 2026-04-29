#!/bin/bash
#
# language-guard-sonarr.sh
# Audits Sonarr episode files for acceptable audio languages, then blocklists,
# deletes, and re-searches bad releases.
#
# Description:
#   Validates imported Sonarr episode files using Sonarr media-language metadata.
#   For English-original series, requires at least one English audio track.
#   For non-English-original series, allows either English or the original language.
#   When a file is invalid, the script:
#   - records a permanent script-level blacklist entry
#   - attempts a Sonarr blacklist for the original release when history exists
#   - deletes the bad episode file through Sonarr
#   - triggers a targeted EpisodeSearch replacement
#
# Usage:
#   ./language-guard-sonarr.sh              # Dry run by default
#   Set DRY_RUN=0 in the script for live runs
#
# Configuration (edit script variables below):
#   - SONARR_URL, SONARR_API_KEY: Sonarr base URL and API key
#   - STATE_FILE, LOG_FILE, LOCK_FILE: Persistent state/log paths and lock path
#   - MAX_ACTIONS_PER_RUN, SEARCH_COOLDOWN_DAYS: Safety limits for batch runs
#   - DELETE_ONLY_IF_REPLACEABLE: Skip unmonitored/non-replaceable content
#   - SERIES_ID, SERIES_FILTER: Optional targeting for testing
#   - USE_FFPROBE_FALLBACK: 1 to use ffprobe when Sonarr metadata is missing
#
# Logging (Unraid-friendly):
#   - Main output goes to stdout so Unraid User Scripts captures it in the GUI.
#   - State is persisted in STATE_FILE to track blacklist entries and run stats.
#   - When LOG_FILE is set, each log line is also appended to that file.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Sonarr
SONARR_URL=""           # e.g. http://192.168.1.10:8989 (no trailing slash)
SONARR_API_KEY=""       # Settings -> General -> API Key

# 1 = dry run (recommended to start), 0 = live run
DRY_RUN="1"

# 1 = extra logging, 0 = normal
DEBUG="0"

# 1 = use ffprobe when Sonarr metadata is missing
USE_FFPROBE_FALLBACK="0"

# Persistent files
LOG_FILE="$SCRIPT_DIR/sonarr-language-guard.log"
STATE_FILE="$SCRIPT_DIR/sonarr-language-guard-state.json"
LOCK_FILE="/tmp/sonarr-language-guard.lock"

# Throttles / safety limits
RATE_LIMIT_SECONDS="1"
MAX_ACTIONS_PER_RUN="25"
SEARCH_COOLDOWN_DAYS="7"

# 1 = only delete when the content is replaceable (recommended)
DELETE_ONLY_IF_REPLACEABLE="1"

# Optional targeting for tests / small batches
SERIES_ID=""
SERIES_FILTER=""

# Optional maintenance toggles
CLEAR_BLACKLIST="0"
BLACKLIST_DUMP="0"
STATS_DUMP="0"

# 1 = faster discovery pass (recommended), 0 = slower shell/jq path
FAST_DISCOVERY="1"

###############################################################################

###############################################################################
# Logging
###############################################################################

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_line() {
  local level="$1"
  shift
  local msg="[$(timestamp)] [$level] $*"
  echo "$msg"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$msg" >> "$LOG_FILE"
  fi
}

debug() {
  if [[ "$DEBUG" == "1" ]]; then
    log_line "DEBUG" "$*"
  fi
}

set_has_line() {
  local haystack="$1"
  local needle="$2"
  printf '%s\n' "$haystack" | grep -F -x -q "$needle"
}

set_add_line() {
  local haystack="$1"
  local needle="$2"
  if set_has_line "$haystack" "$needle"; then
    printf '%s' "$haystack"
  elif [[ -z "$haystack" ]]; then
    printf '%s' "$needle"
  else
    printf '%s\n%s' "$haystack" "$needle"
  fi
}

###############################################################################
# Dependency and environment handling
###############################################################################

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    log_line "ERROR" "Missing required command: $cmd"
    exit 1
  }
}

recover_stale_lock_if_needed() {
  local pid_file lock_pid
  pid_file="$LOCK_FILE/pid"

  [[ -d "$LOCK_FILE" ]] || return 0

  if [[ ! -f "$pid_file" ]]; then
    log_line "WARN" "Recovering stale lock with missing pid file at $LOCK_FILE"
    rm -rf "$LOCK_FILE" >/dev/null 2>&1 || true
    return 0
  fi

  lock_pid="$(tr -dc '0-9' < "$pid_file" 2>/dev/null || true)"
  if [[ -z "$lock_pid" ]]; then
    log_line "WARN" "Recovering stale lock with invalid pid file at $LOCK_FILE"
    rm -rf "$LOCK_FILE" >/dev/null 2>&1 || true
    return 0
  fi

  if kill -0 "$lock_pid" >/dev/null 2>&1; then
    return 1
  fi

  log_line "WARN" "Recovering stale lock at $LOCK_FILE from dead pid=$lock_pid"
  rm -rf "$LOCK_FILE" >/dev/null 2>&1 || true
  return 0
}

acquire_lock() {
  if [[ -d "$LOCK_FILE" ]] && ! recover_stale_lock_if_needed; then
    log_line "ERROR" "Lock already held at $LOCK_FILE"
    exit 1
  fi

  if mkdir "$LOCK_FILE" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_FILE/pid"
    trap 'release_lock' EXIT INT TERM
  else
    log_line "ERROR" "Lock already held at $LOCK_FILE"
    exit 1
  fi
}

release_lock() {
  rm -rf "$LOCK_FILE" >/dev/null 2>&1 || true
}

###############################################################################
# State management
###############################################################################

default_state_json() {
  cat <<'JSON'
{
  "version": 1,
  "blacklist": {},
  "episodes": {},
  "stats": {
    "totals": {
      "live_runs": 0,
      "files_scanned": 0,
      "invalid_files_found": 0,
      "files_deleted": 0,
      "searches_triggered": 0,
      "script_blacklist_additions": 0,
      "script_blacklist_repeat_hits": 0,
      "sonarr_blacklist_successes": 0,
      "sonarr_blacklist_failures": 0,
      "skipped_ambiguous": 0,
      "skipped_cooldown": 0,
      "skipped_unmonitored": 0,
      "skipped_unreplaceable": 0,
      "api_failures": 0,
      "ffprobe_failures": 0
    },
    "runs": []
  }
}
JSON
}

init_state() {
  local state_dir
  state_dir="$(dirname "$STATE_FILE")"
  mkdir -p "$state_dir"

  if [[ ! -f "$STATE_FILE" ]]; then
    default_state_json > "$STATE_FILE"
    return
  fi

  if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
    local backup="${STATE_FILE}.corrupt.$(date +%s)"
    mv "$STATE_FILE" "$backup"
    log_line "WARN" "Corrupt state file moved to $backup"
    default_state_json > "$STATE_FILE"
  fi

  migrate_state
}

migrate_state() {
  state_update '
    .version = (.version // 1)
    | .blacklist = (.blacklist // {})
    | .episodes = (.episodes // {})
    | .stats = (.stats // {})
    | .stats.totals = ((.stats.totals // {}) + {
        "live_runs": (.stats.totals.live_runs // 0),
        "files_scanned": (.stats.totals.files_scanned // 0),
        "invalid_files_found": (.stats.totals.invalid_files_found // 0),
        "files_deleted": (.stats.totals.files_deleted // 0),
        "searches_triggered": (.stats.totals.searches_triggered // 0),
        "script_blacklist_additions": (.stats.totals.script_blacklist_additions // 0),
        "script_blacklist_repeat_hits": (.stats.totals.script_blacklist_repeat_hits // 0),
        "sonarr_blacklist_successes": (.stats.totals.sonarr_blacklist_successes // 0),
        "sonarr_blacklist_failures": (.stats.totals.sonarr_blacklist_failures // 0),
        "skipped_ambiguous": (.stats.totals.skipped_ambiguous // 0),
        "skipped_cooldown": (.stats.totals.skipped_cooldown // 0),
        "skipped_unmonitored": (.stats.totals.skipped_unmonitored // 0),
        "skipped_unreplaceable": (.stats.totals.skipped_unreplaceable // 0),
        "api_failures": (.stats.totals.api_failures // 0),
        "ffprobe_failures": (.stats.totals.ffprobe_failures // 0)
      })
    | .stats.runs = (.stats.runs // [])
  '
}

state_query() {
  local query="$1"
  jq -c "$query" "$STATE_FILE"
}

clear_blacklist_state() {
  state_update '.blacklist = {}'
  log_line "INFO" "Cleared script-level blacklist"
}

dump_blacklist_state() {
  jq '.blacklist' "$STATE_FILE"
}

dump_stats_state() {
  jq '.stats' "$STATE_FILE"
}

###############################################################################
# Sonarr API helpers
###############################################################################

api_get() {
  local path="$1"
  curl -sS -m 60 \
    -H "X-Api-Key: $SONARR_API_KEY" \
    -H "Accept: application/json" \
    "$SONARR_URL$path"
}

api_post() {
  local path="$1"
  local body="${2:-}"
  if [[ -n "$body" ]]; then
    curl -sS -m 60 \
      -X POST \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$SONARR_URL$path"
  else
    curl -sS -m 60 \
      -X POST \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Length: 0" \
      "$SONARR_URL$path"
  fi
}

api_delete_status() {
  local path="$1"
  curl -sS -o /dev/null -w '%{http_code}' -m 60 \
    -X DELETE \
    -H "X-Api-Key: $SONARR_API_KEY" \
    "$SONARR_URL$path"
}

api_post_status() {
  local path="$1"
  local body="${2:-}"
  if [[ -n "$body" ]]; then
    curl -sS -o /dev/null -w '%{http_code}' -m 60 \
      -X POST \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$SONARR_URL$path"
  else
    curl -sS -o /dev/null -w '%{http_code}' -m 60 \
      -X POST \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Length: 0" \
      "$SONARR_URL$path"
  fi
}

api_ok_or_increment_failures() {
  local payload="$1"
  if ! jq empty >/dev/null 2>&1 <<<"$payload"; then
    API_FAILURES=$((API_FAILURES + 1))
    return 1
  fi
  return 0
}

verify_sonarr_connection() {
  local payload
  payload="$(api_get "/api/v3/system/status")" || {
    log_line "ERROR" "Unable to reach Sonarr at $SONARR_URL"
    exit 1
  }

  if ! jq -e '.appName == "Sonarr"' >/dev/null 2>&1 <<<"$payload"; then
    log_line "ERROR" "Target is not Sonarr or API key is invalid"
    exit 1
  fi
}

###############################################################################
# Language normalization
###############################################################################

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

normalize_release_title() {
  local title
  title="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  title="$(printf '%s' "$title" | sed -E 's/[^a-z0-9]+/./g; s/^\.//; s/\.$//; s/\.\.+/./g')"
  printf '%s' "$title"
}

canonical_language() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z]//g')"
  case "$raw" in
    en|eng|english) printf 'english' ;;
    fr|fra|fre|french) printf 'french' ;;
    de|deu|ger|german) printf 'german' ;;
    it|ita|italian) printf 'italian' ;;
    es|spa|spanish) printf 'spanish' ;;
    pt|por|portuguese) printf 'portuguese' ;;
    ptbr|portuguesebrazil|brazilianportuguese) printf 'portuguesebrazil' ;;
    nl|dut|nld|dutch) printf 'dutch' ;;
    da|dan|danish) printf 'danish' ;;
    fi|fin|finnish) printf 'finnish' ;;
    no|nor|norwegian) printf 'norwegian' ;;
    sv|swe|swedish) printf 'swedish' ;;
    pl|pol|polish) printf 'polish' ;;
    ru|rus|russian) printf 'russian' ;;
    uk|ukr|ukrainian) printf 'ukrainian' ;;
    cs|cze|ces|czech) printf 'czech' ;;
    tr|tur|turkish) printf 'turkish' ;;
    ja|jpn|japanese) printf 'japanese' ;;
    ko|kor|korean) printf 'korean' ;;
    zh|chi|zho|chinese) printf 'chinese' ;;
    hi|hin|hindi) printf 'hindi' ;;
    ar|ara|arabic) printf 'arabic' ;;
    el|gre|ell|greek) printf 'greek' ;;
    he|heb|hebrew) printf 'hebrew' ;;
    ro|rum|ron|romanian) printf 'romanian' ;;
    hu|hun|hungarian) printf 'hungarian' ;;
    bg|bul|bulgarian) printf 'bulgarian' ;;
    hr|hrv|croatian) printf 'croatian' ;;
    sr|srp|serbian) printf 'serbian' ;;
    sk|slk|slo|slovak) printf 'slovak' ;;
    sl|slv|slovenian) printf 'slovenian' ;;
    et|est|estonian) printf 'estonian' ;;
    lv|lav|latvian) printf 'latvian' ;;
    lt|lit|lithuanian) printf 'lithuanian' ;;
    fa|per|fas|persian) printf 'persian' ;;
    th|tha|thai) printf 'thai' ;;
    vi|vie|vietnamese) printf 'vietnamese' ;;
    ta|tam|tamil) printf 'tamil' ;;
    ml|mal|malayalam) printf 'malayalam' ;;
    id|ind|indonesian) printf 'indonesian' ;;
    mk|mac|mkd|macedonian) printf 'macedonian' ;;
    ca|cat|catalan) printf 'catalan' ;;
    is|ice|isl|icelandic) printf 'icelandic' ;;
    *) printf '%s' "$raw" ;;
  esac
}

normalize_language_csv() {
  local joined="$1"
  python3 - "$joined" <<'PY'
import re, sys
joined = sys.argv[1]
parts = re.split(r'[^A-Za-z]+', joined)
parts = [p.strip().lower() for p in parts if p.strip()]
print("\n".join(parts))
PY
}

unique_lines() {
  awk 'NF && !seen[$0]++'
}

get_ffprobe_languages() {
  local path="$1"
  ffprobe -v error -select_streams a \
    -show_entries stream_tags=language \
    -of default=noprint_wrappers=1:nokey=1 \
    "$path" 2>/dev/null | unique_lines
}

extract_candidate_languages() {
  local file_json="$1"
  local sonarr_langs sonarr_audio ffprobe_langs path
  sonarr_langs="$(jq -r '(.languages // [])[]?.name // empty' <<<"$file_json" 2>/dev/null || true)"
  sonarr_audio="$(jq -r '.mediaInfo.audioLanguages // empty' <<<"$file_json" 2>/dev/null || true)"
  path="$(jq -r '.path // empty' <<<"$file_json")"

  {
    if [[ -n "$sonarr_langs" ]]; then
      printf '%s\n' "$sonarr_langs"
    fi
    if [[ -n "$sonarr_audio" ]]; then
      normalize_language_csv "$sonarr_audio"
    fi
    if [[ "$USE_FFPROBE_FALLBACK" == "1" && -n "$path" && ( -z "$sonarr_langs" ) && ( -z "$sonarr_audio" || "$sonarr_audio" == "null" ) ]]; then
      if [[ -f "$path" ]]; then
        ffprobe_langs="$(get_ffprobe_languages "$path" || true)"
        if [[ -n "$ffprobe_langs" ]]; then
          printf '%s\n' "$ffprobe_langs"
        else
          FFPROBE_FAILURES=$((FFPROBE_FAILURES + 1))
        fi
      else
        FFPROBE_FAILURES=$((FFPROBE_FAILURES + 1))
      fi
    fi
  } | while IFS= read -r lang; do
    lang="$(trim "$lang")"
    [[ -z "$lang" ]] && continue
    canonical_language "$lang"
    printf '\n'
  done | unique_lines
}

language_list_contains() {
  local wanted="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$wanted" ]] && return 0
  done
  return 1
}

###############################################################################
# Series and episode helpers
###############################################################################

fetch_series_payload() {
  api_get "/api/v3/series"
}

filter_series_payload() {
  local payload="$1"
  jq -c \
    --arg sid "$SERIES_ID" \
    --arg sfilter "$(printf '%s' "$SERIES_FILTER" | tr '[:upper:]' '[:lower:]')" '
      [
        .[]
        | select(($sid == "") or ((.id | tostring) == $sid))
        | select(($sfilter == "") or ((.title | ascii_downcase) | contains($sfilter)))
      ]
    ' <<<"$payload"
}

fetch_episode_files_for_series() {
  local series_id="$1"
  api_get "/api/v3/episodefile?seriesId=${series_id}"
}

fetch_episode_metadata_for_series() {
  local series_id="$1"
  api_get "/api/v3/episode?seriesId=${series_id}"
}

fetch_history_for_episode() {
  local episode_id="$1"
  api_get "/api/v3/history?episodeId=${episode_id}&page=1&pageSize=100&sortKey=date&sortDirection=descending"
}

###############################################################################
# State-derived cooldown and blacklist helpers
###############################################################################

epoch_now() {
  date +%s
}

cooldown_seconds() {
  printf '%s' "$(( SEARCH_COOLDOWN_DAYS * 86400 ))"
}

state_blacklist_has_key() {
  local key="$1"
  jq -e --arg k "$key" '.blacklist[$k] != null' "$STATE_FILE" >/dev/null 2>&1
}

state_add_blacklist_entry() {
  local key="$1"
  local key_type="$2"
  local key_value="$3"
  local series_id="$4"
  local series_title="$5"
  local source_title="$6"
  local reason="$7"
  local now
  now="$(timestamp)"

  if state_blacklist_has_key "$key"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      return
    fi
    state_update "$(cat <<EOF
.blacklist[\$k].last_seen = \$now
| .blacklist[\$k].hit_count = ((.blacklist[\$k].hit_count // 0) + 1)
EOF
)" --arg k "$key" --arg now "$now"
  else
    if [[ "$DRY_RUN" == "1" ]]; then
      SCRIPT_BLACKLIST_ADDITIONS=$((SCRIPT_BLACKLIST_ADDITIONS + 1))
      return
    fi
    state_update "$(cat <<EOF
.blacklist[\$k] = {
  "key_type": \$key_type,
  "key_value": \$key_value,
  "first_seen": \$now,
  "last_seen": \$now,
  "series_id": \$series_id,
  "series_title": \$series_title,
  "example_source_title": \$source_title,
  "reason": \$reason,
  "hit_count": 1
}
EOF
)" --arg k "$key" \
   --arg key_type "$key_type" \
   --arg key_value "$key_value" \
   --argjson series_id "$series_id" \
   --arg series_title "$series_title" \
   --arg source_title "$source_title" \
   --arg reason "$reason" \
   --arg now "$now"
    SCRIPT_BLACKLIST_ADDITIONS=$((SCRIPT_BLACKLIST_ADDITIONS + 1))
  fi
}

state_update() {
  local filter="$1"
  shift || true
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  if jq "$@" "$filter" "$STATE_FILE" > "$tmp"; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
    log_line "ERROR" "Failed to update state"
    exit 1
  fi
}

state_mark_episode_action() {
  local episode_id="$1"
  local status="$2"
  local release_key="$3"
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi
  local now_epoch now_iso
  now_epoch="$(epoch_now)"
  now_iso="$(timestamp)"
  state_update \
    '.episodes[$eid] = ((.episodes[$eid] // {}) + {
      "last_delete_epoch": (if $status == "deleted" then $now_epoch else (.episodes[$eid].last_delete_epoch // 0) end),
      "last_delete_iso": (if $status == "deleted" then $now_iso else (.episodes[$eid].last_delete_iso // "") end),
      "last_search_epoch": (if $status == "search_triggered" then $now_epoch else (.episodes[$eid].last_search_epoch // 0) end),
      "last_search_iso": (if $status == "search_triggered" then $now_iso else (.episodes[$eid].last_search_iso // "") end),
      "last_action_epoch": $now_epoch,
      "last_action_iso": $now_iso,
      "last_status": $status,
      "last_release_key": $release_key,
      "retry_count": ((.episodes[$eid].retry_count // 0) + 1)
    })' \
    --arg eid "$episode_id" \
    --arg status "$status" \
    --arg release_key "$release_key" \
    --argjson now_epoch "$now_epoch" \
    --arg now_iso "$now_iso"
}

state_get_episode_last_action_epoch() {
  local episode_id="$1"
  jq -r --arg eid "$episode_id" '.episodes[$eid].last_search_epoch // 0' "$STATE_FILE"
}

record_run_stats() {
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi

  local now_iso scope_label blacklist_size episode_state_size
  now_iso="$(timestamp)"

  if [[ -n "$SERIES_ID" ]]; then
    scope_label="series_id:$SERIES_ID"
  elif [[ -n "$SERIES_FILTER" ]]; then
    scope_label="series_filter:$SERIES_FILTER"
  else
    scope_label="library:all"
  fi

  blacklist_size="$(jq '.blacklist | length' "$STATE_FILE")"
  episode_state_size="$(jq '.episodes | length' "$STATE_FILE")"

  state_update '
    .stats.totals.live_runs += 1
    | .stats.totals.files_scanned += $files_scanned
    | .stats.totals.invalid_files_found += $invalid_files_found
    | .stats.totals.files_deleted += $files_deleted
    | .stats.totals.searches_triggered += $searches_triggered
    | .stats.totals.script_blacklist_additions += $script_blacklist_additions
    | .stats.totals.script_blacklist_repeat_hits += $script_blacklist_repeat_hits
    | .stats.totals.sonarr_blacklist_successes += $sonarr_blacklist_successes
    | .stats.totals.sonarr_blacklist_failures += $sonarr_blacklist_failures
    | .stats.totals.skipped_ambiguous += $skipped_ambiguous
    | .stats.totals.skipped_cooldown += $skipped_cooldown
    | .stats.totals.skipped_unmonitored += $skipped_unmonitored
    | .stats.totals.skipped_unreplaceable += $skipped_unreplaceable
    | .stats.totals.api_failures += $api_failures
    | .stats.totals.ffprobe_failures += $ffprobe_failures
    | .stats.runs += [{
        "timestamp": $timestamp,
        "scope": $scope,
        "dry_run": false,
        "files_scanned": $files_scanned,
        "valid_files_kept": $valid_files_kept,
        "invalid_files_found": $invalid_files_found,
        "files_deleted": $files_deleted,
        "searches_triggered": $searches_triggered,
        "script_blacklist_additions": $script_blacklist_additions,
        "script_blacklist_repeat_hits": $script_blacklist_repeat_hits,
        "sonarr_blacklist_successes": $sonarr_blacklist_successes,
        "sonarr_blacklist_failures": $sonarr_blacklist_failures,
        "skipped_ambiguous": $skipped_ambiguous,
        "skipped_cooldown": $skipped_cooldown,
        "skipped_unmonitored": $skipped_unmonitored,
        "skipped_unreplaceable": $skipped_unreplaceable,
        "api_failures": $api_failures,
        "ffprobe_failures": $ffprobe_failures,
        "blacklist_size": $blacklist_size,
        "episode_state_size": $episode_state_size
      }]
    | .stats.runs |= (if length > 100 then .[-100:] else . end)
  ' \
    --arg timestamp "$now_iso" \
    --arg scope "$scope_label" \
    --argjson files_scanned "$FILES_SCANNED" \
    --argjson valid_files_kept "$VALID_FILES_KEPT" \
    --argjson invalid_files_found "$INVALID_FILES_FOUND" \
    --argjson files_deleted "$FILES_DELETED" \
    --argjson searches_triggered "$SEARCHES_TRIGGERED" \
    --argjson script_blacklist_additions "$SCRIPT_BLACKLIST_ADDITIONS" \
    --argjson script_blacklist_repeat_hits "$SCRIPT_BLACKLIST_REPEAT_HITS" \
    --argjson sonarr_blacklist_successes "$SONARR_BLACKLIST_SUCCESSES" \
    --argjson sonarr_blacklist_failures "$SONARR_BLACKLIST_FAILURES" \
    --argjson skipped_ambiguous "$SKIPPED_AMBIGUOUS" \
    --argjson skipped_cooldown "$SKIPPED_COOLDOWN" \
    --argjson skipped_unmonitored "$SKIPPED_UNMONITORED" \
    --argjson skipped_unreplaceable "$SKIPPED_UNREPLACEABLE" \
    --argjson api_failures "$API_FAILURES" \
    --argjson ffprobe_failures "$FFPROBE_FAILURES" \
    --argjson blacklist_size "$blacklist_size" \
    --argjson episode_state_size "$episode_state_size"
}

print_state_totals() {
  if [[ ! -f "$STATE_FILE" ]]; then
    return
  fi

  jq -r '
    .stats.totals as $t |
    "State totals:\n" +
    "  Live runs: \($t.live_runs)\n" +
    "  Files scanned: \($t.files_scanned)\n" +
    "  Invalid files found: \($t.invalid_files_found)\n" +
    "  Files deleted: \($t.files_deleted)\n" +
    "  Searches triggered: \($t.searches_triggered)\n" +
    "  Script blacklist additions: \($t.script_blacklist_additions)\n" +
    "  Script blacklist repeat hits: \($t.script_blacklist_repeat_hits)\n" +
    "  Sonarr blacklist successes: \($t.sonarr_blacklist_successes)\n" +
    "  Sonarr blacklist failures: \($t.sonarr_blacklist_failures)"
  ' "$STATE_FILE"
}

episode_in_cooldown() {
  local episode_id="$1"
  local last_epoch now
  last_epoch="$(state_get_episode_last_action_epoch "$episode_id")"
  now="$(epoch_now)"
  [[ $(( now - last_epoch )) -lt $(cooldown_seconds) ]]
}

###############################################################################
# Sonarr destructive actions
###############################################################################

delete_episode_file() {
  local file_id="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_line "INFO" "DRY_RUN delete episode file id=$file_id"
    return 0
  fi

  local code
  code="$(api_delete_status "/api/v3/episodefile/${file_id}")" || code="000"
  if [[ "$code" =~ ^20[0-9]$ ]]; then
    FILES_DELETED=$((FILES_DELETED + 1))
    return 0
  fi

  API_FAILURES=$((API_FAILURES + 1))
  log_line "WARN" "Failed to delete episode file id=$file_id http=$code"
  return 1
}

search_episodes() {
  local episode_ids_csv="$1"
  local body
  body="$(jq -cn --argjson ids "[$episode_ids_csv]" '{name:"EpisodeSearch", episodeIds:$ids}')"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_line "INFO" "DRY_RUN trigger episode search ids=[$episode_ids_csv]"
    return 0
  fi

  local code
  code="$(api_post_status "/api/v3/command" "$body")" || code="000"
  if [[ "$code" =~ ^20[0-9]$ ]]; then
    SEARCHES_TRIGGERED=$((SEARCHES_TRIGGERED + 1))
    return 0
  fi

  API_FAILURES=$((API_FAILURES + 1))
  log_line "WARN" "Failed to trigger episode search http=$code ids=[$episode_ids_csv]"
  return 1
}

attempt_sonarr_blacklist() {
  local history_id="$1"
  local source_title="$2"
  if [[ -z "$history_id" || "$history_id" == "null" ]]; then
    SONARR_BLACKLIST_FAILURES=$((SONARR_BLACKLIST_FAILURES + 1))
    log_line "WARN" "sonarr_blacklist_failed no_history_id source=$source_title"
    return 1
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log_line "INFO" "DRY_RUN Sonarr blacklist history_id=$history_id source=$source_title"
    return 0
  fi

  local code
  code="$(api_post_status "/api/v3/history/failed/${history_id}")" || code="000"
  if [[ "$code" =~ ^20[0-9]$ ]]; then
    SONARR_BLACKLIST_SUCCESSES=$((SONARR_BLACKLIST_SUCCESSES + 1))
    return 0
  fi

  SONARR_BLACKLIST_FAILURES=$((SONARR_BLACKLIST_FAILURES + 1))
  log_line "WARN" "sonarr_blacklist_failed history_id=$history_id http=$code source=$source_title"
  return 1
}

###############################################################################
# History resolution
###############################################################################

find_matching_history() {
  local episode_id="$1"
  local file_id="$2"
  local path="$3"
  local scene_name="$4"
  local history

  history="$(fetch_history_for_episode "$episode_id")" || {
    API_FAILURES=$((API_FAILURES + 1))
    printf '{}'
    return
  }

  jq -c \
    --argjson file_id "$file_id" \
    --arg path "$path" \
    --arg scene_name "$scene_name" '
      .records
      | (
          map(select(.data.fileId? == ($file_id|tostring) or .data.fileId? == $file_id))
          + map(select(.data.importedPath? == $path))
          + map(select(.sourceTitle? == $scene_name))
        )
      | unique_by(.id)
      | sort_by(.date)
      | reverse
      | {
          imported: (map(select(.eventType == "downloadFolderImported"))[0] // null),
          grabbed: (map(select(.eventType == "grabbed"))[0] // null)
        }
    ' <<<"$history"
}

resolve_release_identity() {
  local history_json="$1"
  local fallback_title="$2"
  jq -c --arg fallback_title "$fallback_title" '
    .imported as $imported
    | .grabbed as $grabbed
    | {
        history_id: ($grabbed.id // $imported.id // null),
        guid: ($grabbed.data.guid // $imported.data.guid // null),
        download_id: ($grabbed.downloadId // $imported.downloadId // null),
        source_title: ($grabbed.sourceTitle // $imported.sourceTitle // $fallback_title),
        imported_event_id: ($imported.id // null),
        grabbed_event_id: ($grabbed.id // null)
      }
  ' <<<"$history_json"
}

###############################################################################
# Replaceability and monitored checks
###############################################################################

episode_ids_csv_from_file() {
  local file_json="$1"
  local episodes_json="$2"
  local direct_ids file_id
  direct_ids="$(jq -r '
    if (.episodeIds // []) | length > 0
    then (.episodeIds | map(tostring) | join(","))
    else ""
    end
  ' <<<"$file_json")"
  if [[ -n "$direct_ids" ]]; then
    printf '%s' "$direct_ids"
    return
  fi
  file_id="$(jq -r '.id' <<<"$file_json")"
  jq -r \
    --argjson file_id "$file_id" '
      [
        .[]
        | select((.episodeFileId // 0) == $file_id)
        | .id
        | tostring
      ] | join(",")
    ' <<<"$episodes_json"
}

episode_any_unmonitored() {
  local episodes_json="$1"
  local episode_ids_csv="$2"
  jq -e --arg ids "$episode_ids_csv" '
    ($ids | split(",") | map(tonumber)) as $wanted
    | any(.[]; (.id as $id | ($wanted | index($id))) != null and (.monitored != true))
  ' <<<"$episodes_json" >/dev/null 2>&1
}

file_replaceable() {
  local series_json="$1"
  local episodes_json="$2"
  local episode_ids_csv="$3"

  if [[ "$(jq -r '.monitored // false' <<<"$series_json")" != "true" ]]; then
    return 1
  fi

  if episode_any_unmonitored "$episodes_json" "$episode_ids_csv"; then
    return 1
  fi

  return 0
}

file_has_unmonitored_content() {
  local series_json="$1"
  local episodes_json="$2"
  local episode_ids_csv="$3"

  if [[ "$(jq -r '.monitored // false' <<<"$series_json")" != "true" ]]; then
    return 0
  fi

  if episode_any_unmonitored "$episodes_json" "$episode_ids_csv"; then
    return 0
  fi

  return 1
}

###############################################################################
# Main file processing
###############################################################################

process_invalid_file() {
  local series_json="$1"
  local file_json="$2"
  local episodes_json="$3"
  local reason="$4"
  local detected_langs="$5"

  local series_id series_title file_id path scene_name episode_ids_csv history_json identity_json
  local guid source_title normalized_title primary_key secondary_key history_id
  local blacklist_repeat="0" release_key=""

  series_id="$(jq -r '.id' <<<"$series_json")"
  series_title="$(jq -r '.title' <<<"$series_json")"
  file_id="$(jq -r '.id' <<<"$file_json")"
  path="$(jq -r '.path // empty' <<<"$file_json")"
  scene_name="$(jq -r '.sceneName // empty' <<<"$file_json")"
  episode_ids_csv="$(episode_ids_csv_from_file "$file_json" "$episodes_json")"

  INVALID_FILES_FOUND=$((INVALID_FILES_FOUND + 1))

  if [[ -z "$episode_ids_csv" ]]; then
    SKIPPED_AMBIGUOUS=$((SKIPPED_AMBIGUOUS + 1))
    log_line "WARN" "skip_ambiguous no_episode_ids series=\"$series_title\" file_id=$file_id path=\"$path\""
    return
  fi

  local episode_id
  IFS=',' read -r -a episode_ids <<<"$episode_ids_csv"
  for episode_id in "${episode_ids[@]}"; do
    if episode_in_cooldown "$episode_id"; then
      SKIPPED_COOLDOWN=$((SKIPPED_COOLDOWN + 1))
      log_line "INFO" "skip_cooldown series=\"$series_title\" episode_id=$episode_id file_id=$file_id"
      return
    fi
  done

  if [[ "$DELETE_ONLY_IF_REPLACEABLE" == "1" ]] && ! file_replaceable "$series_json" "$episodes_json" "$episode_ids_csv"; then
    if file_has_unmonitored_content "$series_json" "$episodes_json" "$episode_ids_csv"; then
      SKIPPED_UNMONITORED=$((SKIPPED_UNMONITORED + 1))
      log_line "INFO" "skip_unmonitored series=\"$series_title\" file_id=$file_id episodes=[$episode_ids_csv]"
    else
      SKIPPED_UNREPLACEABLE=$((SKIPPED_UNREPLACEABLE + 1))
      log_line "INFO" "skip_unreplaceable series=\"$series_title\" file_id=$file_id episodes=[$episode_ids_csv]"
    fi
    return
  fi

  history_json="$(find_matching_history "${episode_ids[0]}" "$file_id" "$path" "$scene_name")"
  identity_json="$(resolve_release_identity "$history_json" "$scene_name")"
  guid="$(jq -r '.guid // empty' <<<"$identity_json")"
  source_title="$(jq -r '.source_title // empty' <<<"$identity_json")"
  history_id="$(jq -r '.history_id // empty' <<<"$identity_json")"
  normalized_title="$(normalize_release_title "${source_title:-${scene_name:-$(basename "$path")}}")"

  if [[ -n "$guid" ]]; then
    primary_key="guid:$guid"
    release_key="$primary_key"
  else
    primary_key=""
  fi

  secondary_key="title:$normalized_title"
  [[ -z "$release_key" ]] && release_key="$secondary_key"

  if [[ -n "$primary_key" ]] && state_blacklist_has_key "$primary_key"; then
    blacklist_repeat="1"
  elif state_blacklist_has_key "$secondary_key"; then
    blacklist_repeat="1"
  fi

  if [[ "$blacklist_repeat" == "1" ]]; then
    SCRIPT_BLACKLIST_REPEAT_HITS=$((SCRIPT_BLACKLIST_REPEAT_HITS + 1))
    log_line "WARN" "blacklist_repeat series=\"$series_title\" file_id=$file_id release=\"$source_title\""
  fi

  if [[ -n "$primary_key" ]]; then
    state_add_blacklist_entry "$primary_key" "guid" "$guid" "$series_id" "$series_title" "${source_title:-$scene_name}" "$reason"
  fi
  state_add_blacklist_entry "$secondary_key" "title" "$normalized_title" "$series_id" "$series_title" "${source_title:-$scene_name}" "$reason"

  log_line "INFO" \
    "invalid_file series=\"$series_title\" file_id=$file_id path=\"$path\" detected_languages=\"${detected_langs//$'\n'/,}\" reason=\"$reason\" source_title=\"${source_title:-$scene_name}\""

  attempt_sonarr_blacklist "$history_id" "${source_title:-$scene_name}" || true

  if (( ACTION_COUNT >= MAX_ACTIONS_PER_RUN )); then
    log_line "INFO" "max_actions_reached count=$ACTION_COUNT"
    return
  fi

  if set_has_line "$SEEN_FILE_ACTIONS" "$file_id"; then
    debug "File already handled in this run file_id=$file_id"
    return
  fi

  if delete_episode_file "$file_id"; then
    SEEN_FILE_ACTIONS="$(set_add_line "$SEEN_FILE_ACTIONS" "$file_id")"
    ACTION_COUNT=$((ACTION_COUNT + 1))
    sleep "$RATE_LIMIT_SECONDS"
    local search_ids=()
    for episode_id in "${episode_ids[@]}"; do
      if ! set_has_line "$SEEN_EPISODE_SEARCHES" "$episode_id"; then
        search_ids+=("$episode_id")
        SEEN_EPISODE_SEARCHES="$(set_add_line "$SEEN_EPISODE_SEARCHES" "$episode_id")"
      fi
      state_mark_episode_action "$episode_id" "deleted" "$release_key"
    done

    if ((${#search_ids[@]} > 0)); then
      local csv
      csv="$(IFS=,; printf '%s' "${search_ids[*]}")"
      if search_episodes "$csv"; then
        for episode_id in "${search_ids[@]}"; do
          state_mark_episode_action "$episode_id" "search_triggered" "$release_key"
        done
      fi
    fi
  fi
}

process_invalid_candidate() {
  local candidate_json="$1"
  local series_id series_title reason detected_langs
  local series_json episodes_json file_json

  series_id="$(jq -r '.series_id' <<<"$candidate_json")"
  series_title="$(jq -r '.series_title' <<<"$candidate_json")"
  reason="$(jq -r '.reason' <<<"$candidate_json")"
  detected_langs="$(jq -r '.detected_languages | join(",")' <<<"$candidate_json")"

  series_json="$(jq -c '{
    id: .series_id,
    title: .series_title,
    monitored: true
  }' <<<"$candidate_json")"
  episodes_json="$(jq -c '.episode_meta' <<<"$candidate_json")"
  file_json="$(jq -c '{
    id: .file_id,
    path: .path,
    sceneName: (.scene_name // ""),
    episodeIds: (.episode_ids // [])
  }' <<<"$candidate_json")"

  process_invalid_file "$series_json" "$file_json" "$episodes_json" "$reason" "$detected_langs"
}

process_file() {
  local series_json="$1"
  local file_json="$2"
  local episodes_json="$3"
  local original_language raw_langs
  local detected_langs=()
  local acceptable_langs=()
  local lang

  FILES_SCANNED=$((FILES_SCANNED + 1))
  if (( FILES_SCANNED % 250 == 0 )); then
    log_line "INFO" "progress files_scanned=$FILES_SCANNED invalid_found=$INVALID_FILES_FOUND actions=$ACTION_COUNT"
  fi
  original_language="$(jq -r '.originalLanguage.name // empty' <<<"$series_json" | while IFS= read -r l; do canonical_language "$l"; done)"

  while IFS= read -r lang; do
    [[ -n "$lang" ]] && detected_langs+=("$lang")
  done < <(extract_candidate_languages "$file_json")

  if [[ ${#detected_langs[@]} -eq 0 ]]; then
    SKIPPED_AMBIGUOUS=$((SKIPPED_AMBIGUOUS + 1))
    log_line "WARN" "skip_ambiguous no_languages file_id=$(jq -r '.id' <<<"$file_json") path=\"$(jq -r '.path' <<<"$file_json")\""
    return
  fi

  acceptable_langs=("english")
  if [[ -n "$original_language" && "$original_language" != "english" ]]; then
    acceptable_langs+=("$original_language")
  fi

  for lang in "${detected_langs[@]}"; do
    if language_list_contains "$lang" "${acceptable_langs[@]}"; then
      VALID_FILES_KEPT=$((VALID_FILES_KEPT + 1))
      debug "keep_file file_id=$(jq -r '.id' <<<"$file_json") acceptable_language=$lang"
      return
    fi
  done

  local reason
  if [[ "$original_language" == "english" || -z "$original_language" ]]; then
    reason="missing_english_audio"
  else
    reason="missing_english_and_original_audio"
  fi

  raw_langs="$(printf '%s\n' "${detected_langs[@]}" | paste -sd ',' -)"
  process_invalid_file "$series_json" "$file_json" "$episodes_json" "$reason" "$raw_langs"
}

process_series() {
  local series_json="$1"
  local series_id series_title episode_files_json episodes_json
  series_id="$(jq -r '.id' <<<"$series_json")"
  series_title="$(jq -r '.title' <<<"$series_json")"
  SERIES_SCANNED=$((SERIES_SCANNED + 1))

  log_line "INFO" "scan_series count=$SERIES_SCANNED title=\"$series_title\" id=$series_id"

  episode_files_json="$(fetch_episode_files_for_series "$series_id")" || {
    API_FAILURES=$((API_FAILURES + 1))
    log_line "WARN" "Failed to fetch episode files for series=\"$series_title\""
    return
  }

  episodes_json="$(fetch_episode_metadata_for_series "$series_id")" || {
    API_FAILURES=$((API_FAILURES + 1))
    log_line "WARN" "Failed to fetch episodes metadata for series=\"$series_title\""
    return
  }

  local file_json
  while IFS= read -r file_json; do
    [[ -z "$file_json" ]] && continue
    process_file "$series_json" "$file_json" "$episodes_json"
    if (( ACTION_COUNT >= MAX_ACTIONS_PER_RUN )); then
      log_line "INFO" "Stopping after MAX_ACTIONS_PER_RUN=$MAX_ACTIONS_PER_RUN"
      return
    fi
  done < <(jq -c '.[]' <<<"$episode_files_json")
}

discover_candidates_fast() {
  SONARR_URL="$SONARR_URL" \
  SONARR_API_KEY="$SONARR_API_KEY" \
  SERIES_ID="$SERIES_ID" \
  SERIES_FILTER="$SERIES_FILTER" \
  python3 - <<'PY'
import concurrent.futures, json, os, re, sys, threading, urllib.request

SONARR_URL = os.environ["SONARR_URL"].rstrip("/")
API_KEY = os.environ["SONARR_API_KEY"]
SERIES_ID = os.environ.get("SERIES_ID", "")
SERIES_FILTER = os.environ.get("SERIES_FILTER", "").lower()
MAX_WORKERS = 12

def api_get(path):
    req = urllib.request.Request(
        f"{SONARR_URL}{path}",
        headers={"X-Api-Key": API_KEY, "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)

def canon(raw):
    raw = re.sub(r"[^a-z]", "", str(raw).lower())
    mapping = {
        "en": "english", "eng": "english", "english": "english",
        "fr": "french", "fra": "french", "fre": "french", "french": "french",
        "de": "german", "deu": "german", "ger": "german", "german": "german",
        "it": "italian", "ita": "italian", "italian": "italian",
        "es": "spanish", "spa": "spanish", "spanish": "spanish",
        "pt": "portuguese", "por": "portuguese", "portuguese": "portuguese",
        "ru": "russian", "rus": "russian", "russian": "russian",
        "ja": "japanese", "jpn": "japanese", "japanese": "japanese",
    }
    return mapping.get(raw, raw)

def audio_langs(file_obj):
    found = []
    for lang in file_obj.get("languages", []) or []:
        value = canon(lang.get("name", ""))
        if value and value not in found:
            found.append(value)
    audio = ((file_obj.get("mediaInfo") or {}).get("audioLanguages") or "").strip()
    if audio:
        for part in re.split(r"[^A-Za-z]+", audio):
            value = canon(part)
            if value and value not in found:
                found.append(value)
    return found

series_list = api_get("/api/v3/series")
if SERIES_ID:
    series_list = [s for s in series_list if str(s.get("id")) == SERIES_ID]
if SERIES_FILTER:
    series_list = [s for s in series_list if SERIES_FILTER in (s.get("title","").lower())]

summary = {
    "series_scanned": 0,
    "files_scanned": 0,
    "valid_files_kept": 0,
    "invalid_files_found": 0,
    "skipped_ambiguous": 0,
    "skipped_unmonitored": 0,
}
candidates = []
progress_lock = threading.Lock()

def inspect_series(series):
    local_summary = {
        "series_scanned": 1,
        "files_scanned": 0,
        "valid_files_kept": 0,
        "invalid_files_found": 0,
        "skipped_ambiguous": 0,
        "skipped_unmonitored": 0,
    }
    local_candidates = []
    series_id = series["id"]
    episodes = api_get(f"/api/v3/episode?seriesId={series_id}")
    files = api_get(f"/api/v3/episodefile?seriesId={series_id}")
    episode_map = {}
    for ep in episodes:
        episode_map.setdefault(ep.get("episodeFileId", 0), []).append({
            "id": ep["id"],
            "monitored": ep.get("monitored", False),
        })
    original = canon(((series.get("originalLanguage") or {}).get("name")) or "")
    acceptable = {"english"}
    if original and original != "english":
        acceptable.add(original)
    for file_obj in files:
        local_summary["files_scanned"] += 1
        file_id = file_obj["id"]
        linked = episode_map.get(file_id, [])
        if not linked:
            local_summary["skipped_ambiguous"] += 1
            continue
        if (not series.get("monitored", False)) or any(not ep["monitored"] for ep in linked):
            local_summary["skipped_unmonitored"] += 1
            continue
        langs = audio_langs(file_obj)
        if not langs:
            local_summary["skipped_ambiguous"] += 1
            continue
        if any(lang in acceptable for lang in langs):
            local_summary["valid_files_kept"] += 1
            continue
        local_summary["invalid_files_found"] += 1
        reason = "missing_english_audio" if (not original or original == "english") else "missing_english_and_original_audio"
        local_candidates.append({
            "series_id": series_id,
            "series_title": series.get("title"),
            "file_id": file_id,
            "path": file_obj.get("path"),
            "scene_name": file_obj.get("sceneName"),
            "episode_ids": [ep["id"] for ep in linked],
            "episode_meta": [{"id": ep["id"], "monitored": ep["monitored"]} for ep in linked],
            "reason": reason,
            "detected_languages": langs,
        })
    return local_summary, local_candidates

completed = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
    futures = [ex.submit(inspect_series, series) for series in series_list]
    for future in concurrent.futures.as_completed(futures):
        local_summary, local_candidates = future.result()
        for key, value in local_summary.items():
            summary[key] += value
        candidates.extend(local_candidates)
        with progress_lock:
            completed += 1
            if completed % 25 == 0:
                print(json.dumps({"progress": completed}), flush=True)

print(json.dumps({"summary": summary, "candidates": candidates}), flush=True)
PY
}

print_summary() {
  cat <<EOF
Summary:
  Files scanned: $FILES_SCANNED
  Valid files kept: $VALID_FILES_KEPT
  Invalid files found: $INVALID_FILES_FOUND
  Script blacklist additions: $SCRIPT_BLACKLIST_ADDITIONS
  Script blacklist repeat hits: $SCRIPT_BLACKLIST_REPEAT_HITS
  Sonarr blacklist successes: $SONARR_BLACKLIST_SUCCESSES
  Sonarr blacklist failures: $SONARR_BLACKLIST_FAILURES
  Files deleted: $FILES_DELETED
  Searches triggered: $SEARCHES_TRIGGERED
  Skipped ambiguous: $SKIPPED_AMBIGUOUS
  Skipped cooldown: $SKIPPED_COOLDOWN
  Skipped unmonitored: $SKIPPED_UNMONITORED
  Skipped unreplaceable: $SKIPPED_UNREPLACEABLE
  API failures: $API_FAILURES
  ffprobe failures: $FFPROBE_FAILURES
EOF
  if [[ "$DRY_RUN" != "1" ]]; then
    print_state_totals
  fi
}

main() {
  require_cmd bash
  require_cmd curl
  require_cmd jq
  require_cmd python3
  if [[ "$USE_FFPROBE_FALLBACK" == "1" ]]; then
    require_cmd ffprobe
  fi

  if [[ -z "$SONARR_API_KEY" ]]; then
    log_line "ERROR" "SONARR_API_KEY is required"
    exit 1
  fi

  # Runtime counters (not editable config)
  FILES_SCANNED=0
  INVALID_FILES_FOUND=0
  VALID_FILES_KEPT=0
  SCRIPT_BLACKLIST_ADDITIONS=0
  SCRIPT_BLACKLIST_REPEAT_HITS=0
  SONARR_BLACKLIST_SUCCESSES=0
  SONARR_BLACKLIST_FAILURES=0
  FILES_DELETED=0
  SEARCHES_TRIGGERED=0
  SKIPPED_AMBIGUOUS=0
  SKIPPED_COOLDOWN=0
  SKIPPED_UNMONITORED=0
  SKIPPED_UNREPLACEABLE=0
  API_FAILURES=0
  FFPROBE_FAILURES=0
  ACTION_COUNT=0
  SERIES_SCANNED=0

  SEEN_FILE_ACTIONS=""
  SEEN_EPISODE_SEARCHES=""

  acquire_lock
  init_state
  verify_sonarr_connection

  if [[ "$CLEAR_BLACKLIST" == "1" ]]; then
    clear_blacklist_state
    exit 0
  fi

  if [[ "$BLACKLIST_DUMP" == "1" ]]; then
    dump_blacklist_state
    exit 0
  fi

  if [[ "$STATS_DUMP" == "1" ]]; then
    dump_stats_state
    exit 0
  fi

  local series_payload filtered_series
  series_payload="$(fetch_series_payload)" || {
    log_line "ERROR" "Failed to fetch series list"
    exit 1
  }

  if [[ "$FAST_DISCOVERY" == "1" ]]; then
    local discovery_output progress_lines discovery_json
    discovery_output="$(discover_candidates_fast)"
    progress_lines="$(printf '%s\n' "$discovery_output" | jq -cr 'select(.progress?)' 2>/dev/null || true)"
    if [[ -n "$progress_lines" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        log_line "INFO" "scan_progress series_scanned=$(jq -r '.progress' <<<"$line")"
      done <<<"$progress_lines"
    fi
    discovery_json="$(printf '%s\n' "$discovery_output" | tail -n 1)"
    if ! jq -e '.summary and .candidates' >/dev/null 2>&1 <<<"$discovery_json"; then
      log_line "ERROR" "Fast discovery failed"
      exit 1
    fi
    SERIES_SCANNED="$(jq -r '.summary.series_scanned' <<<"$discovery_json")"
    FILES_SCANNED="$(jq -r '.summary.files_scanned' <<<"$discovery_json")"
    VALID_FILES_KEPT="$(jq -r '.summary.valid_files_kept' <<<"$discovery_json")"
    INVALID_FILES_FOUND=0
    SKIPPED_AMBIGUOUS="$(jq -r '.summary.skipped_ambiguous' <<<"$discovery_json")"
    SKIPPED_UNMONITORED="$(jq -r '.summary.skipped_unmonitored' <<<"$discovery_json")"
    log_line "INFO" "fast_discovery_complete series_scanned=$SERIES_SCANNED files_scanned=$FILES_SCANNED candidates=$(jq '.candidates | length' <<<"$discovery_json")"
    local candidate_json
    while IFS= read -r candidate_json; do
      [[ -z "$candidate_json" ]] && continue
      process_invalid_candidate "$candidate_json"
      if (( ACTION_COUNT >= MAX_ACTIONS_PER_RUN )); then
        log_line "INFO" "Stopping after MAX_ACTIONS_PER_RUN=$MAX_ACTIONS_PER_RUN"
        break
      fi
    done < <(jq -c '.candidates[]' <<<"$discovery_json")
  else
    filtered_series="$(filter_series_payload "$series_payload")"
    if [[ "$(jq 'length' <<<"$filtered_series")" -eq 0 ]]; then
      log_line "WARN" "No series matched filters"
      exit 0
    fi

    local series_json
    while IFS= read -r series_json; do
      [[ -z "$series_json" ]] && continue
      process_series "$series_json"
      if (( ACTION_COUNT >= MAX_ACTIONS_PER_RUN )); then
        break
      fi
    done < <(jq -c '.[]' <<<"$filtered_series")
  fi

  record_run_stats
  print_summary
}

main "$@"
