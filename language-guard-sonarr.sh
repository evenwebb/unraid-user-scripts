#!/bin/bash
#
# language-guard-sonarr.sh
# Audit Sonarr episode audio languages; fix bad releases via blocklist, delete, and search.
#
# Description:
#   Same language rules as language-guard-radarr.sh for TV episodes.
#   Defaults to dry run — set DRY_RUN=0 for live remediation.
#
# Usage:
#   ./language-guard-sonarr.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only (default), 0 = delete/blocklist/search
#
# Configuration (edit script variables below):
#   - SONARR_URL / SONARR_API_KEY: Sonarr connection
#   - DRY_RUN / DEBUG / USE_FFPROBE_FALLBACK
#   - DELETE_ONLY_IF_REPLACEABLE: 1 = skip unmonitored or unreplaceable content
#   - LOG_FILE / STATE_FILE / LOCK_FILE
#   - RATE_LIMIT_DELAY / MAX_ACTIONS_PER_RUN / SEARCH_COOLDOWN_DAYS
#   - SERIES_ID / SERIES_FILTER: optional targeting
#   - CLEAR_BLACKLIST / BLACKLIST_DUMP / STATS_DUMP
#   - FAST_DISCOVERY: 1 = faster Python discovery (recommended)
#
# Requires: curl, jq, python3 (ffprobe optional if USE_FFPROBE_FALLBACK=1)
#
# Note: Progress and errors print to stdout; Unraid User Scripts shows that in the run window. Optional LOG_FILE also appends a copy to disk.
#
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# --- Sonarr ---
SONARR_URL=""           # e.g. http://192.168.1.10:8989 (no trailing slash)
SONARR_API_KEY=""       # Settings → General → API Key

DRY_RUN="1"             # 1 = preview only (recommended first), 0 = apply changes
DEBUG="0"               # 1 = extra logging, 0 = normal
USE_FFPROBE_FALLBACK="0"  # 1 = probe media with ffprobe when Sonarr language metadata is missing

# Persistent files (empty = default beside this script)
LOG_FILE=""
STATE_FILE=""
LOCK_FILE="/tmp/sonarr-language-guard.lock"

RATE_LIMIT_DELAY="1"    # Seconds between API calls
MAX_ACTIONS_PER_RUN="25"  # Max delete/search actions per run
SEARCH_COOLDOWN_DAYS="7"  # Min days before re-searching the same title

DELETE_ONLY_IF_REPLACEABLE="1"  # 1 = only delete when Sonarr can replace the release (recommended)

SERIES_ID=""            # Limit to one Sonarr series ID (empty = full library)
SERIES_FILTER=""        # Substring match on series title (empty = all)

# Script state maintenance (not Sonarr's release blocklist API)
CLEAR_BLACKLIST="0"     # 1 = clear script blacklist state and exit
BLACKLIST_DUMP="0"      # 1 = print script blacklist JSON and exit
STATS_DUMP="0"          # 1 = print script stats JSON and exit

FAST_DISCOVERY="1"      # 1 = faster Python discovery (recommended), 0 = Bash/jq discovery

###############################################################################

[[ -z "$LOG_FILE" ]] && LOG_FILE="$SCRIPT_DIR/sonarr-language-guard.log"
[[ -z "$STATE_FILE" ]] && STATE_FILE="$SCRIPT_DIR/sonarr-language-guard-state.json"
[[ -n "${RATE_LIMIT_SECONDS:-}" ]] && RATE_LIMIT_DELAY="$RATE_LIMIT_SECONDS"

###############################################################################

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
    local msg="[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && printf '%s\n' "$msg" >> "$LOG_FILE"
}
log_err() {
    local msg="[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ERROR: $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && printf '%s\n' "$msg" >> "$LOG_FILE"
}

# Validate LOG_FILE path (reject path traversal)
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    log_err "LOG_FILE path is not allowed. Choose a normal file path without '..'."
    exit 1
fi

log_line() {
  local level="$1"
  shift
  local msg="[$(timestamp)] [$level] $*"
  if [[ "$level" == "DEBUG" ]]; then
    echo "$msg" >&2
  else
    echo "$msg"
  fi
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$msg" >> "$LOG_FILE"
  fi
}

debug() {
  if [[ "$DEBUG" == "1" ]]; then
    log_line "DEBUG" "$*"
  fi
}

_friendly_curl_err() {
  local msg="$1"
  msg="${msg#curl: }"
  if [[ "$msg" == *"Could not resolve host"* ]]; then
    echo "The server name could not be found — check the IP address or hostname in the script."
  elif [[ "$msg" == *"Connection refused"* ]]; then
    echo "Connection refused — is Sonarr running and is the port number correct?"
  elif [[ "$msg" == *"Failed to connect"* ]]; then
    echo "Could not connect — check that Sonarr is running and the URL is correct."
  elif [[ "$msg" == *"timed out"* ]] || [[ "$msg" == *"Timeout"* ]]; then
    echo "The connection timed out — check the URL and network."
  elif [[ "$msg" == *"Unauthorized"* ]] || [[ "$msg" == *"401"* ]]; then
    echo "Login was rejected — wrong API key."
  else
    echo "$msg"
  fi
}

_log_service_failure() {
  local service="$1" task="$2" url="$3" code="$4" body="$5" curl_err="${6:-}" fix_hint="${7:-Check the URL and API key in this script.}"
  if [[ -n "$curl_err" ]]; then
    log_line "ERROR" "Could not reach ${service} while ${task}. $(_friendly_curl_err "$curl_err") ${fix_hint}"
    return
  fi
  case "$code" in
    401) log_line "ERROR" "Wrong API key for ${service} while ${task}. ${fix_hint}" ;;
    403) log_line "ERROR" "${service} refused access while ${task}. ${fix_hint}" ;;
    404) log_line "ERROR" "Could not find ${service} at ${url} while ${task}. Check SONARR_URL in this script — it should look like http://your-server:8989 with no extra path." ;;
    000|"") log_line "ERROR" "Could not connect to ${service} at ${url} while ${task}. Check SONARR_URL, that Sonarr is running, and that the port is correct." ;;
    *)
      if [[ -n "$body" ]] && ! printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
        log_line "ERROR" "${service} replied with an unexpected page (not JSON) while ${task}. The URL may be wrong — check SONARR_URL in this script."
      else
        log_line "ERROR" "${service} returned an error while ${task}. ${fix_hint}"
      fi
      ;;
  esac
}

# Run jq with JSON from a bash variable via pipe only (never <<< here-strings on JSON:
# smart quotes / GUI paste bugs cause "unexpected EOF" and subtle parse errors).
jq_read() {
  local _jq_json="$1"
  shift || return 2
  printf '%s' "$_jq_json" | jq "$@"
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
  cat <<'SONARR_LANGUAGE_DEFAULT_STATE_JSON'
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
SONARR_LANGUAGE_DEFAULT_STATE_JSON
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
  local task="${2:-talking to Sonarr}"
  local url="${SONARR_URL}${path}"
  local resp code body curl_err fix_hint
  fix_hint="Check SONARR_URL and SONARR_API_KEY in this script (Sonarr → Settings → General → API Key)."
  curl_err=$(mktemp) || return 1
  resp=$(curl -sS -m 60 -w "\n%{http_code}" \
    -H "X-Api-Key: $SONARR_API_KEY" \
    -H "Accept: application/json" \
    "$url" 2>"$curl_err") || {
    _log_service_failure "Sonarr" "$task" "$SONARR_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" "$fix_hint"
    rm -f "$curl_err"
    return 1
  }
  rm -f "$curl_err"
  code=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')
  if [[ "$code" != "200" ]] || ! printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    _log_service_failure "Sonarr" "$task" "$SONARR_URL" "$code" "$body" "" "$fix_hint"
    return 1
  fi
  printf '%s' "$body"
  return 0
}

_sonarr_api_status() {
  local method="$1" path="$2" task="$3" body="${4:-}"
  local url="${SONARR_URL}${path}" code curl_err fix_hint
  fix_hint="Check SONARR_URL and SONARR_API_KEY in this script (Sonarr → Settings → General → API Key)."
  curl_err=$(mktemp) || { echo "000"; return 1; }
  if [[ "$method" == "POST" && -n "$body" ]]; then
    code=$(curl -sS -m 60 -o /dev/null -w '%{http_code}' \
      -X POST \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$url" 2>"$curl_err") || {
      _log_service_failure "Sonarr" "$task" "$SONARR_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" "$fix_hint"
      rm -f "$curl_err"
      echo "000"
      return 1
    }
  elif [[ "$method" == "POST" ]]; then
    code=$(curl -sS -m 60 -o /dev/null -w '%{http_code}' \
      -X POST \
      -H "X-Api-Key: $SONARR_API_KEY" \
      -H "Content-Length: 0" \
      "$url" 2>"$curl_err") || {
      _log_service_failure "Sonarr" "$task" "$SONARR_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" "$fix_hint"
      rm -f "$curl_err"
      echo "000"
      return 1
    }
  else
    code=$(curl -sS -m 60 -o /dev/null -w '%{http_code}' \
      -X "$method" \
      -H "X-Api-Key: $SONARR_API_KEY" \
      "$url" 2>"$curl_err") || {
      _log_service_failure "Sonarr" "$task" "$SONARR_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" "$fix_hint"
      rm -f "$curl_err"
      echo "000"
      return 1
    }
  fi
  rm -f "$curl_err"
  if [[ ! "$code" =~ ^2 ]]; then
    _log_service_failure "Sonarr" "$task" "$SONARR_URL" "$code" "" "" "$fix_hint"
  fi
  echo "$code"
  [[ "$code" =~ ^2 ]]
}

api_delete_status() {
  local path="$1" task="${2:-updating Sonarr}"
  _sonarr_api_status "DELETE" "$path" "$task" ""
}

api_post_status() {
  local path="$1" body="${2:-}" task="${3:-updating Sonarr}"
  _sonarr_api_status "POST" "$path" "$task" "$body"
}

api_ok_or_increment_failures() {
  local payload="$1"
  if ! jq_read "$payload" empty >/dev/null 2>&1; then
    API_FAILURES=$((API_FAILURES + 1))
    return 1
  fi
  return 0
}

verify_sonarr_connection() {
  local payload app_name
  if [[ -z "$SONARR_URL" ]]; then
    log_line "ERROR" "SONARR_URL is not set. Edit the settings at the top of this script."
    exit 1
  fi
  SONARR_URL="${SONARR_URL%/}"
  if [[ ! "$SONARR_URL" =~ ^https?:// ]]; then
    log_line "ERROR" "SONARR_URL must be a full web address starting with http:// or https:// (you entered: ${SONARR_URL})"
    exit 1
  fi
  payload="$(api_get "/api/v3/system/status" "checking the connection")" || exit 1
  app_name="$(jq_read "$payload" -r '.appName // empty')"
  if [[ "$app_name" != "Sonarr" ]]; then
    log_line "ERROR" "Connected but the response was not from Sonarr — check SONARR_URL and SONARR_API_KEY in this script."
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
  python3 -c 'import re, sys; joined = sys.argv[1]; parts = [p.strip().lower() for p in re.split(r"[^A-Za-z]+", joined) if p.strip()]; sys.stdout.write("\n".join(parts) + "\n")' "$joined"
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
  sonarr_langs="$(jq_read "$file_json" -r '(.languages // [])[]?.name // empty' 2>/dev/null || true)"
  sonarr_audio="$(jq_read "$file_json" -r '.mediaInfo.audioLanguages // empty' 2>/dev/null || true)"
  path="$(jq_read "$file_json" -r '.path // empty')"

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

single_non_english_language() {
  local found="" lang
  for lang in "$@"; do
    [[ -z "$lang" || "$lang" == "english" || "$lang" == "unknown" ]] && continue
    if [[ -z "$found" ]]; then
      found="$lang"
    elif [[ "$lang" != "$found" ]]; then
      return 1
    fi
  done
  [[ -n "$found" ]] || return 1
  printf '%s' "$found"
}

###############################################################################
# Series and episode helpers
###############################################################################

fetch_series_payload() {
  api_get "/api/v3/series" "loading the series list"
}

filter_series_payload() {
  local payload="$1"
  jq_read "$payload" -c \
    --arg sid "$SERIES_ID" \
    --arg sfilter "$(printf '%s' "$SERIES_FILTER" | tr '[:upper:]' '[:lower:]')" '
      [
        .[]
        | select(($sid == "") or ((.id | tostring) == $sid))
        | select(($sfilter == "") or ((.title | ascii_downcase) | contains($sfilter)))
      ]
    '
}

fetch_episode_files_for_series() {
  local series_id="$1"
  api_get "/api/v3/episodefile?seriesId=${series_id}" "loading episode files"
}

fetch_episode_metadata_for_series() {
  local series_id="$1"
  api_get "/api/v3/episode?seriesId=${series_id}" "loading episode metadata"
}

fetch_history_for_episode() {
  local episode_id="$1"
  api_get "/api/v3/history?episodeId=${episode_id}&page=1&pageSize=100&sortKey=date&sortDirection=descending" "loading download history"
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

  LAST_BLACKLIST_ENTRY_WAS_NEW=0

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
      LAST_BLACKLIST_ENTRY_WAS_NEW=1
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
    LAST_BLACKLIST_ENTRY_WAS_NEW=1
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
    "Lifetime (state file, all live runs combined):\n" +
    "  Live runs: \($t.live_runs)\n" +
    "  Files scanned: \($t.files_scanned)\n" +
    "  Invalid files found: \($t.invalid_files_found)\n" +
    "  Files deleted: \($t.files_deleted)\n" +
    "  Searches triggered: \($t.searches_triggered)\n" +
    "  New releases (script blacklist, runs combined): \($t.script_blacklist_additions)\n" +
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
  code="$(api_delete_status "/api/v3/episodefile/${file_id}" "deleting episode file ${file_id}")" || code="000"
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
  code="$(api_post_status "/api/v3/command" "$body" "searching for replacement episodes")" || code="000"
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
  code="$(api_post_status "/api/v3/history/failed/${history_id}" "" "blocklisting a failed release")" || code="000"
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

  jq_read "$history" -c \
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
    '
}

resolve_release_identity() {
  local history_json="$1"
  local fallback_title="$2"
  jq_read "$history_json" -c --arg fallback_title "$fallback_title" '
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
  '
}

###############################################################################
# Replaceability and monitored checks
###############################################################################

episode_ids_csv_from_file() {
  local file_json="$1"
  local episodes_json="$2"
  local direct_ids file_id
  direct_ids="$(jq_read "$file_json" -r '
    if (.episodeIds // []) | length > 0
    then (.episodeIds | map(tostring) | join(","))
    else ""
    end
  ')"
  if [[ -n "$direct_ids" ]]; then
    printf '%s' "$direct_ids"
    return
  fi
  file_id="$(jq_read "$file_json" -r '.id')"
  jq_read "$episodes_json" -r \
    --argjson file_id "$file_id" '
      [
        .[]
        | select((.episodeFileId // 0) == $file_id)
        | .id
        | tostring
      ] | join(",")
    '
}

episode_any_unmonitored() {
  local episodes_json="$1"
  local episode_ids_csv="$2"
  jq_read "$episodes_json" -e --arg ids "$episode_ids_csv" '
    ($ids | split(",") | map(tonumber)) as $wanted
    | any(.[]; (.id as $id | ($wanted | index($id))) != null and (.monitored != true))
  ' >/dev/null 2>&1
}

file_replaceable() {
  local series_json="$1"
  local episodes_json="$2"
  local episode_ids_csv="$3"

  if ! jq_read "$series_json" -e '.monitored == true' >/dev/null 2>&1; then
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

  if ! jq_read "$series_json" -e '.monitored == true' >/dev/null 2>&1; then
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

  series_id="$(jq_read "$series_json" -r '.id')"
  series_title="$(jq_read "$series_json" -r '.title')"
  file_id="$(jq_read "$file_json" -r '.id')"
  path="$(jq_read "$file_json" -r '.path // empty')"
  scene_name="$(jq_read "$file_json" -r '.sceneName // empty')"
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
  guid="$(jq_read "$identity_json" -r '.guid // empty')"
  source_title="$(jq_read "$identity_json" -r '.source_title // empty')"
  history_id="$(jq_read "$identity_json" -r '.history_id // empty')"
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

  local blacklist_added_this_file=0
  if [[ -n "$primary_key" ]]; then
    state_add_blacklist_entry "$primary_key" "guid" "$guid" "$series_id" "$series_title" "${source_title:-$scene_name}" "$reason"
    [[ "${LAST_BLACKLIST_ENTRY_WAS_NEW:-0}" -eq 1 ]] && blacklist_added_this_file=1
  fi
  state_add_blacklist_entry "$secondary_key" "title" "$normalized_title" "$series_id" "$series_title" "${source_title:-$scene_name}" "$reason"
  [[ "${LAST_BLACKLIST_ENTRY_WAS_NEW:-0}" -eq 1 ]] && blacklist_added_this_file=1

  [[ "$blacklist_added_this_file" -eq 1 ]] && SCRIPT_BLACKLIST_ADDITIONS=$((SCRIPT_BLACKLIST_ADDITIONS + 1))

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
    sleep "$RATE_LIMIT_DELAY"
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

  series_id="$(jq_read "$candidate_json" -r '.series_id')"
  series_title="$(jq_read "$candidate_json" -r '.series_title')"
  reason="$(jq_read "$candidate_json" -r '.reason')"
  detected_langs="$(jq_read "$candidate_json" -r '.detected_languages | join(",")')"

  series_json="$(jq_read "$candidate_json" -c '{
    id: .series_id,
    title: .series_title,
    monitored: true
  }')"
  episodes_json="$(jq_read "$candidate_json" -c '.episode_meta')"
  file_json="$(jq_read "$candidate_json" -c '{
    id: .file_id,
    path: .path,
    sceneName: (.scene_name // ""),
    episodeIds: (.episode_ids // [])
  }')"

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

  if ! jq_read "$file_json" -e '.id != null' >/dev/null 2>&1; then
    return
  fi

  FILES_SCANNED=$((FILES_SCANNED + 1))
  if (( FILES_SCANNED % 250 == 0 )); then
    log_line "INFO" "progress files_scanned=$FILES_SCANNED invalid_found=$INVALID_FILES_FOUND actions=$ACTION_COUNT"
  fi
  original_language="$(jq_read "$series_json" -r '.originalLanguage.name // empty' | while IFS= read -r l; do canonical_language "$l"; done)"
  [[ "$original_language" == "unknown" ]] && original_language=""

  while IFS= read -r lang; do
    [[ -n "$lang" ]] && detected_langs+=("$lang")
  done < <(extract_candidate_languages "$file_json")

  if [[ ${#detected_langs[@]} -eq 0 ]]; then
    SKIPPED_AMBIGUOUS=$((SKIPPED_AMBIGUOUS + 1))
    log_line "WARN" "skip_ambiguous no_languages file_id=$(jq_read "$file_json" -r '.id') path=\"$(jq_read "$file_json" -r '.path')\""
    return
  fi

  if [[ -z "$original_language" ]]; then
    local inferred_original=""
    inferred_original="$(single_non_english_language "${detected_langs[@]}")" || inferred_original=""
    if [[ -n "$inferred_original" ]]; then
      SKIPPED_AMBIGUOUS=$((SKIPPED_AMBIGUOUS + 1))
      log_line "WARN" "skip_ambiguous missing_original_language file_id=$(jq_read "$file_json" -r '.id') inferred_original=$inferred_original path=\"$(jq_read "$file_json" -r '.path')\""
      return
    fi
  fi

  acceptable_langs=("english")
  if [[ -n "$original_language" && "$original_language" != "english" ]]; then
    acceptable_langs+=("$original_language")
  fi

  for lang in "${detected_langs[@]}"; do
    if language_list_contains "$lang" "${acceptable_langs[@]}"; then
      VALID_FILES_KEPT=$((VALID_FILES_KEPT + 1))
      debug "keep_file file_id=$(jq_read "$file_json" -r '.id') acceptable_language=$lang"
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
  local series_id="" series_title="" episode_files_json="" episodes_json="" file_json=""

  series_id="$(jq_read "$series_json" -r '.id')"
  series_title="$(jq_read "$series_json" -r '.title')"
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

  while IFS= read -r file_json; do
    [[ -z "$file_json" ]] && continue
    process_file "$series_json" "$file_json" "$episodes_json"
    if (( ACTION_COUNT >= MAX_ACTIONS_PER_RUN )); then
      log_line "INFO" "Stopping after MAX_ACTIONS_PER_RUN=$MAX_ACTIONS_PER_RUN"
      return
    fi
  done < <(jq_read "${episode_files_json:-[]}" -c ".[]")
}

discover_candidates_fast() {
  SONARR_URL="$SONARR_URL" \
  SONARR_API_KEY="$SONARR_API_KEY" \
  SERIES_ID="$SERIES_ID" \
  SERIES_FILTER="$SERIES_FILTER" \
  python3 - <<'SONARR_FAST_DISCOVERY'

import concurrent.futures
import json
import os
import re
import threading
import urllib.request

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
        "ptbr": "portuguesebrazil", "portuguesebrazil": "portuguesebrazil", "brazilianportuguese": "portuguesebrazil",
        "nl": "dutch", "dut": "dutch", "nld": "dutch", "dutch": "dutch",
        "da": "danish", "dan": "danish", "danish": "danish",
        "fi": "finnish", "fin": "finnish", "finnish": "finnish",
        "no": "norwegian", "nor": "norwegian", "norwegian": "norwegian",
        "sv": "swedish", "swe": "swedish", "swedish": "swedish",
        "ru": "russian", "rus": "russian", "russian": "russian",
        "uk": "ukrainian", "ukr": "ukrainian", "ukrainian": "ukrainian",
        "pl": "polish", "pol": "polish", "polish": "polish",
        "cs": "czech", "cze": "czech", "ces": "czech", "czech": "czech",
        "tr": "turkish", "tur": "turkish", "turkish": "turkish",
        "ja": "japanese", "jpn": "japanese", "japanese": "japanese",
        "ko": "korean", "kor": "korean", "korean": "korean",
        "zh": "chinese", "chi": "chinese", "zho": "chinese", "chinese": "chinese",
        "hi": "hindi", "hin": "hindi", "hindi": "hindi",
        "ar": "arabic", "ara": "arabic", "arabic": "arabic",
        "el": "greek", "gre": "greek", "ell": "greek", "greek": "greek",
        "he": "hebrew", "heb": "hebrew", "hebrew": "hebrew",
        "ro": "romanian", "rum": "romanian", "ron": "romanian", "romanian": "romanian",
        "hu": "hungarian", "hun": "hungarian", "hungarian": "hungarian",
        "bg": "bulgarian", "bul": "bulgarian", "bulgarian": "bulgarian",
        "ca": "catalan", "cat": "catalan", "catalan": "catalan",
        "is": "icelandic", "ice": "icelandic", "isl": "icelandic", "icelandic": "icelandic",
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


def main():
    series_list = api_get("/api/v3/series")
    if SERIES_ID:
        series_list = [s for s in series_list if str(s.get("id")) == SERIES_ID]
    if SERIES_FILTER:
        series_list = [s for s in series_list if SERIES_FILTER in (s.get("title", "").lower())]

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
        if original == "unknown":
            original = ""
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
            inferred_non_english = sorted({lang for lang in langs if lang and lang not in {"english", "unknown"}})
            if not original and len(inferred_non_english) == 1:
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
main()
SONARR_FAST_DISCOVERY
}


print_summary() {
  cat <<EOF
This run:
  Files scanned: $FILES_SCANNED
  Valid files kept: $VALID_FILES_KEPT
  Invalid files found: $INVALID_FILES_FOUND
  New releases recorded in script blacklist: $SCRIPT_BLACKLIST_ADDITIONS
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
    log_line "ERROR" "SONARR_API_KEY is not set. Edit the settings at the top of this script (Sonarr → Settings → General → API Key)."
    exit 1
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    log_line "INFO" "DRY-RUN: no deletions, blocklists, or searches will be performed"
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
  series_payload="$(fetch_series_payload)" || exit 1

  if [[ "$FAST_DISCOVERY" == "1" ]]; then
    local discovery_output progress_lines discovery_json cand_len candidate_json
    discovery_output="$(discover_candidates_fast)"
    progress_lines="$(jq_read "$discovery_output" -cr "select(.progress?)" 2>/dev/null || true)"
    if [[ -n "$progress_lines" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        log_line "INFO" "scan_progress series_scanned=$(jq_read "$line" -r ".progress")"
      done <<<"$progress_lines"
    fi
    discovery_json="$(printf '%s\n' "$discovery_output" | tail -n 1)"
    if ! jq_read "$discovery_json" -e ".summary and .candidates" >/dev/null 2>&1; then
      log_line "ERROR" "Fast discovery failed"
      exit 1
    fi
    SERIES_SCANNED="$(jq_read "$discovery_json" -r ".summary.series_scanned")"
    FILES_SCANNED="$(jq_read "$discovery_json" -r ".summary.files_scanned")"
    VALID_FILES_KEPT="$(jq_read "$discovery_json" -r ".summary.valid_files_kept")"
    INVALID_FILES_FOUND=0
    SKIPPED_AMBIGUOUS="$(jq_read "$discovery_json" -r ".summary.skipped_ambiguous")"
    SKIPPED_UNMONITORED="$(jq_read "$discovery_json" -r ".summary.skipped_unmonitored")"
    cand_len="$(jq_read "$discovery_json" ".candidates | length")"
    log_line "INFO" "fast_discovery_complete series_scanned=$SERIES_SCANNED files_scanned=$FILES_SCANNED candidates=$cand_len"
    while IFS= read -r candidate_json; do
      [[ -z "$candidate_json" ]] && continue
      process_invalid_candidate "$candidate_json"
      if (( ACTION_COUNT >= MAX_ACTIONS_PER_RUN )); then
        log_line "INFO" "Stopping after MAX_ACTIONS_PER_RUN=$MAX_ACTIONS_PER_RUN"
        break
      fi
    done < <(jq_read "$discovery_json" -c ".candidates[]")
  else
    filtered_series="$(filter_series_payload "$series_payload")"
    if ! jq_read "$filtered_series" -e "length > 0" >/dev/null 2>&1; then
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
    done < <(jq_read "$filtered_series" -c ".[]")
  fi

  record_run_stats
  print_summary
}

main "$@"
