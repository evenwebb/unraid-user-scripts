#!/bin/bash
#
# queue-sync-nzbget.sh
# Sync Sonarr/Radarr queues with NZBGet; remove stale items and trigger search.
#
# Description:
#   Removes *arr queue entries when the download left NZBGet, optionally blocklists, and searches again.
#
# Usage:
#   ./queue-sync-nzbget.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#   DRY_RUN: 1 = preview only, 0 = apply changes
#
# Configuration (edit script variables below):
#   - RADARR_URL / RADARR_API_KEY / SKIP_RADARR
#   - SONARR_URL / SONARR_API_KEY / SKIP_SONARR
#   - NZBGET_URL / NZBGET_USER / NZBGET_PASS
#   - DRY_RUN / TRIGGER_SEARCH / BLOCKLIST_ENABLED / CLEAR_NZBGET_FAILED
#   - SAFE_EMPTY_QUEUE / LOCK_FILE / MAX_REMOVALS_PER_RUN
#   - RATE_LIMIT_DELAY / RETRY_COUNT / LOG_FILE / CURL_TIMEOUT
#   - SEARCH_IDS_CHUNK_SIZE / QUEUE_PAGE_SIZE / CLEAR_NZBGET_AGE_DAYS
#
# Requires: curl, jq (flock if LOCK_FILE is set)
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

# --- Radarr ---
RADARR_URL=""           # e.g. http://192.168.1.10:7878 (no trailing slash)
RADARR_API_KEY=""       # Settings → General → API Key

# --- Sonarr ---
SONARR_URL=""           # e.g. http://192.168.1.10:8989 (no trailing slash)
SONARR_API_KEY=""       # Settings → General → API Key

# --- NZBGet ---
NZBGET_URL=""           # e.g. http://192.168.1.10:6789 (no trailing slash)
NZBGET_USER="nzbget"    # ControlUsername
NZBGET_PASS=""         # ControlPassword

# --- Behaviour ---
DRY_RUN="0"                # 1 = log only, no removals or searches
TRIGGER_SEARCH="1"         # 0 = remove+blocklist only; 1 = remove, blocklist, and force search
CLEAR_NZBGET_FAILED="0"    # 1 = clear failed downloads from NZBGet history
BLOCKLIST_ENABLED="1"      # 1 = blocklist release when removing from *arr queue; 0 = remove only
SKIP_RADARR="0"            # 1 = skip Radarr processing
SKIP_SONARR="0"            # 1 = skip Sonarr processing
SAFE_EMPTY_QUEUE="0"       # 1 = skip *arr removals when NZBGet queue is empty
LOCK_FILE=""               # Prevent concurrent runs (e.g. /tmp/queue-sync-nzbget.lock)
MAX_REMOVALS_PER_RUN="0"   # Cap removals per run; 0 = no limit
RATE_LIMIT_DELAY="0"       # Seconds between API calls when removing; 0 = no delay
RETRY_COUNT="0"            # Retries for failed curl requests
CLEAR_NZBGET_AGE_DAYS="0"  # Only clear failed history older than N days; 0 = all
LOG_FILE=""               # If set, append logs here (e.g. /boot/config/queue-sync.log)
CURL_TIMEOUT="30"
SEARCH_IDS_CHUNK_SIZE="50"  # Max IDs per MoviesSearch/EpisodeSearch request
QUEUE_PAGE_SIZE="500"      # *arr queue page size (pagination handled)

###############################################################################

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
    echo "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

# Log a line built with printf so *arr titles (user/API-controlled) are never
# re-parsed as shell (titles may contain $(), backticks, or %).
log_fmt() {
    local _msg
    # shellcheck disable=SC2059
    printf -v _msg "$@" || return
    log "$_msg"
}

_require_http_url() {
    local name="$1" val="$2"
    if [[ ! "$val" =~ ^https?:// ]]; then
        log_err "${name} must be a full web address starting with http:// or https:// (you entered: ${val})"
        exit 1
    fi
}

# Validate *arr config only when enabled (SKIP_*=0). Skipped apps are ignored entirely.
_validate_enabled_arr() {
    local app="$1" skip_var="$2" url_var="$3" key_var="$4"
    local skip_val url_val key_val
    skip_val="${!skip_var}"
    url_val="${!url_var}"
    key_val="${!key_var}"
    [[ "$skip_val" == "1" ]] && return 0
    if [[ -z "$url_val" || -z "$key_val" ]]; then
        log_err "${app} is turned on (${skip_var}=0) but ${url_var} and/or ${key_var} are missing. Edit the settings at the top of this script."
        exit 1
    fi
    _require_http_url "$url_var" "$url_val"
}

# Turn raw curl output into a short, readable reason.
_friendly_curl_err() {
    local msg="$1"
    msg="${msg#curl: }"
    if [[ "$msg" == *"Could not resolve host"* ]]; then
        echo "The server name could not be found — check the IP address or hostname in the script."
    elif [[ "$msg" == *"Connection refused"* ]]; then
        echo "Connection refused — is the app running and is the port number correct?"
    elif [[ "$msg" == *"Failed to connect"* ]]; then
        echo "Could not connect — check that the app is running and the URL is correct."
    elif [[ "$msg" == *"timed out"* ]] || [[ "$msg" == *"Timeout"* ]]; then
        echo "The connection timed out — check the URL and network."
    elif [[ "$msg" == *"Unauthorized"* ]] || [[ "$msg" == *"401"* ]]; then
        echo "Login was rejected — wrong username, password, or API key."
    else
        echo "$msg"
    fi
}

radarr_queue_fields() {
    jq -r '[.protocol // "", .downloadId // "", .movieId // "", .title // "?", .id] | @tsv'
}

sonarr_queue_fields() {
    jq -r '[.protocol // "", .downloadId // "", .title // "?", .id, (([
      .episodeId,
      .episode.id,
      .episode.episodeId,
      (.episodes[]?.id),
      (.episodes[]?.episodeId)
    ] | map(select(. != null and . != "")) | unique | join(","))), (.seriesId // .series?.id // "")] | @tsv'
}

# Runtime normalization and validation (not part of editable config)

# Strip trailing slashes
RADARR_URL="${RADARR_URL%/}"
SONARR_URL="${SONARR_URL%/}"
NZBGET_URL="${NZBGET_URL%/}"
NZBGET_JSONRPC="${NZBGET_URL}/jsonrpc"

# Require at least NZBGet to be configured (script is NZBGet-centric)
if [[ -z "$NZBGET_URL" || -z "$NZBGET_PASS" ]]; then
    log_err "NZBGet is not configured. Set NZBGET_URL and NZBGET_PASS at the top of this script."
    exit 1
fi
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        log_err "Required program '$cmd' is not installed on this server."
        exit 1
    fi
done

# Validate URLs (reject file://, relative paths, etc.)
_require_http_url "NZBGET_URL" "$NZBGET_URL"
_validate_enabled_arr "Radarr" "SKIP_RADARR" "RADARR_URL" "RADARR_API_KEY"
_validate_enabled_arr "Sonarr" "SKIP_SONARR" "SONARR_URL" "SONARR_API_KEY"

if [[ -z "$NZBGET_USER" ]]; then
    log_err "NZBGET_USER is empty. Set it to the Control Username from NZBGet → Settings → Security."
    exit 1
fi

# Validate LOG_FILE path (reject path traversal)
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    log_err "LOG_FILE path is not allowed. Choose a normal file path without '..'."
    exit 1
fi

# Validate numeric config (prevent infinite loops)
if [[ ! "$SEARCH_IDS_CHUNK_SIZE" =~ ^[1-9][0-9]*$ ]] || [[ ! "$QUEUE_PAGE_SIZE" =~ ^[1-9][0-9]*$ ]]; then
    log_err "SEARCH_IDS_CHUNK_SIZE and QUEUE_PAGE_SIZE must be whole numbers greater than zero."
    exit 1
fi
if [[ ! "$RETRY_COUNT" =~ ^[0-9]+$ ]] || [[ ! "$MAX_REMOVALS_PER_RUN" =~ ^[0-9]+$ ]] || [[ ! "$RATE_LIMIT_DELAY" =~ ^[0-9]+$ ]] || [[ ! "$CLEAR_NZBGET_AGE_DAYS" =~ ^[0-9]+$ ]]; then
    log_err "RETRY_COUNT, MAX_REMOVALS_PER_RUN, RATE_LIMIT_DELAY, and CLEAR_NZBGET_AGE_DAYS must be whole numbers (0 or greater)."
    exit 1
fi

# Acquire lock if LOCK_FILE is set
if [[ -n "$LOCK_FILE" ]]; then
    if [[ "$LOCK_FILE" == *".."* || "$LOCK_FILE" == "-"* ]]; then
        log_err "LOCK_FILE path is not allowed. Choose a normal file path without '..'."
        exit 1
    fi
    lock_dir=$(dirname "$LOCK_FILE")
    if [[ -n "$lock_dir" && "$lock_dir" != "." && ! -d "$lock_dir" ]]; then
        log_err "LOCK_FILE folder does not exist: $lock_dir"
        exit 1
    fi
    if ! command -v flock &>/dev/null; then
        log_err "LOCK_FILE is set but the 'flock' command is not available on this server."
        exit 1
    fi
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_err "Another copy of this script is already running. If that is wrong, delete the lock file: $LOCK_FILE"
        exit 1
    fi
fi

# Wrapper for curl with retry; pass through all curl args
_curl() {
    local attempt=0 r
    while true; do
        curl "$@"
        r=$?
        [[ $r -eq 0 ]] && return 0
        ((attempt++))
        [[ $attempt -gt "$RETRY_COUNT" ]] && return $r
        sleep 1
    done
}

_rate_limit() {
    [[ "$RATE_LIMIT_DELAY" -gt 0 ]] && sleep "$RATE_LIMIT_DELAY"
}

# Log connection/auth failures in plain language (never log passwords or API keys).
_log_service_failure() {
    local service="$1" task="$2" url="$3" code="$4" body="$5" curl_err="${6:-}" fix_hint="${7:-Check the URL and login details in this script.}"
    if [[ -n "$curl_err" ]]; then
        log_err "Could not reach ${service} while ${task}. $(_friendly_curl_err "$curl_err") ${fix_hint}"
        return
    fi
    case "$code" in
        401) log_err "Wrong username, password, or API key for ${service} while ${task}. ${fix_hint}" ;;
        403) log_err "${service} refused access while ${task}. ${fix_hint}" ;;
        404) log_err "Could not find ${service} at ${url} while ${task}. Check the URL in this script — it should look like http://your-server:port with no extra path." ;;
        000|"") log_err "Could not connect to ${service} at ${url} while ${task}. Check the URL, that the app is running, and that the port is correct." ;;
        *)
            if [[ -n "$body" ]] && ! jq -e . <<< "$body" &>/dev/null; then
                log_err "${service} replied with an unexpected page (not JSON) while ${task}. The URL may be wrong — check it in this script. Address tried: ${url}"
            else
                log_err "${service} returned an error while ${task}. ${fix_hint} (address: ${url})"
            fi
            ;;
    esac
}

# NZBGet JSON-RPC call; prints response body on success. $2 = plain-English task description.
_nzbget_rpc() {
    local task="$1" json_body="$2"
    local resp code body curl_err nzbget_fix
    nzbget_fix="Check NZBGET_URL, NZBGET_USER (currently '${NZBGET_USER}'), and NZBGET_PASS in this script (NZBGet → Settings → Security)."
    curl_err=$(mktemp) || return 1
    resp=$(_curl -s -S -m "${CURL_TIMEOUT}" -u "${NZBGET_USER}:${NZBGET_PASS}" -X POST \
      -H "Content-Type: application/json" \
      -d "$json_body" -w "\n%{http_code}" \
      "${NZBGET_JSONRPC}" 2>"$curl_err") || {
      _log_service_failure "NZBGet" "$task" "$NZBGET_URL" "" "" "$(tr '\n' ' ' <"$curl_err")" "$nzbget_fix"
      rm -f "$curl_err"
      return 1
    }
    rm -f "$curl_err"
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "200" ]]; then
      _log_service_failure "NZBGet" "$task" "$NZBGET_URL" "$code" "$body" "" "$nzbget_fix"
      return 1
    fi
    if ! jq -e . <<< "$body" &>/dev/null; then
      log_err "NZBGet sent back an unexpected response while ${task}. Check NZBGET_URL in this script (currently ${NZBGET_URL})."
      return 1
    fi
    if jq -e '.error' <<< "$body" &>/dev/null; then
      log_err "NZBGet reported a problem while ${task}: $(jq -r '.error.message // .error.code // .error' <<< "$body")"
      return 1
    fi
    printf '%s' "$body"
    return 0
}

# Verify *arr URL + API key before queue processing.
_arr_verify_auth() {
    local app="$1" base_url="$2" api_key="$3"
    local resp code body curl_err arr_fix
    case "$app" in
        Radarr) arr_fix="Check RADARR_URL and RADARR_API_KEY in this script (Radarr → Settings → General → API Key)." ;;
        Sonarr) arr_fix="Check SONARR_URL and SONARR_API_KEY in this script (Sonarr → Settings → General → API Key)." ;;
        *) arr_fix="Check the URL and API key for ${app} in this script." ;;
    esac
    curl_err=$(mktemp) || return 1
    resp=$(_curl -s -S -m "${CURL_TIMEOUT}" -w "\n%{http_code}" \
      -H "X-Api-Key: ${api_key}" -H "Accept: application/json" \
      "${base_url}/api/v3/system/status" 2>"$curl_err") || {
      _log_service_failure "$app" "checking the connection" "$base_url" "" "" "$(tr '\n' ' ' <"$curl_err")" "$arr_fix"
      rm -f "$curl_err"
      return 1
    }
    rm -f "$curl_err"
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "200" ]] || ! jq -e . <<< "$body" &>/dev/null; then
      _log_service_failure "$app" "checking the connection" "$base_url" "$code" "$body" "" "$arr_fix"
      return 1
    fi
    return 0
}

# Call *arr command API; on failure log HTTP status and response body (for debugging).
# Usage: _arr_command_post "Radarr" "$RADARR_URL" "$RADARR_API_KEY" '{"name":"MoviesSearch","movieIds":[1]}' "MoviesSearch (chunk 1)"
# Logs success message and returns 0, or logs error (with status/body) and returns 1.
_arr_command_post() {
    local app="$1" base_url="$2" api_key="$3" json_body="$4" task="$5"
    local resp code body curl_err arr_fix
    case "$app" in
        Radarr) arr_fix="Check RADARR_URL and RADARR_API_KEY in this script." ;;
        Sonarr) arr_fix="Check SONARR_URL and SONARR_API_KEY in this script." ;;
        *) arr_fix="Check the URL and API key for ${app} in this script." ;;
    esac
    curl_err=$(mktemp) || return 1
    resp=$(_curl -s -S -m "${CURL_TIMEOUT}" -w "\n%{http_code}" -X POST \
      -H "X-Api-Key: ${api_key}" -H "Content-Type: application/json" \
      -d "$json_body" "${base_url}/api/v3/command" 2>"$curl_err") || {
      _log_service_failure "$app" "$task" "$base_url" "" "" "$(tr '\n' ' ' <"$curl_err")" "$arr_fix"
      rm -f "$curl_err"
      return 1
    }
    rm -f "$curl_err"
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "2"* ]]; then
      _log_service_failure "$app" "$task" "$base_url" "$code" "$body" "" "$arr_fix"
      return 1
    fi
    log "${app}: triggered ${task}"
    _rate_limit
    return 0
}

# Remove one *arr queue item; logs connection/auth failures in plain language.
_arr_queue_delete() {
    local app="$1" base_url="$2" api_key="$3" qid="$4" blocklist_val="$5"
    local resp code body curl_err arr_fix task
    task="removing queue item ${qid}"
    case "$app" in
        Radarr) arr_fix="Check RADARR_URL and RADARR_API_KEY in this script." ;;
        Sonarr) arr_fix="Check SONARR_URL and SONARR_API_KEY in this script." ;;
        *) arr_fix="Check the URL and API key for ${app} in this script." ;;
    esac
    curl_err=$(mktemp) || return 1
    resp=$(_curl -s -S -m "${CURL_TIMEOUT}" -w "\n%{http_code}" -X DELETE \
      -H "X-Api-Key: ${api_key}" \
      "${base_url}/api/v3/queue/${qid}?removeFromClient=true&blocklist=${blocklist_val}" 2>"$curl_err") || {
      _log_service_failure "$app" "$task" "$base_url" "" "" "$(tr '\n' ' ' <"$curl_err")" "$arr_fix"
      rm -f "$curl_err"
      return 1
    }
    rm -f "$curl_err"
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "2"* ]]; then
      _log_service_failure "$app" "$task" "$base_url" "$code" "$body" "" "$arr_fix"
      return 1
    fi
    return 0
}

# --- Fetch NZBGet queue IDs ---
nzbget_ids_raw=$(_nzbget_rpc "reading the NZBGet download queue" '{"jsonrpc":"2.0","method":"listgroups","params":[0],"id":1}') || exit 1

if [[ "$(jq -r '.result | type' <<< "$nzbget_ids_raw" 2>/dev/null)" != "array" ]]; then
  log_err "NZBGet sent an unexpected response while reading the download queue. Check NZBGET_URL in this script (currently ${NZBGET_URL})."
  exit 1
fi
nzbget_ids=$(jq -r '.result[]?.NZBID // empty' <<< "$nzbget_ids_raw" 2>/dev/null)

# Build lookup set for O(1) check (avoids linear scan per *arr queue item)
declare -A nzbget_set=()
while IFS= read -r nid; do
    [[ -n "$nid" ]] && nzbget_set[$nid]=1
done <<< "$nzbget_ids"

# Global removals counter for MAX_REMOVALS_PER_RUN
removals_count=0

# Summary counters (useful for DRY_RUN decisions)
radarr_stale_count=0
sonarr_stale_count=0
radarr_removed_count=0
sonarr_removed_count=0
radarr_remove_failures=0
sonarr_remove_failures=0
radarr_unique_movies_search=0
sonarr_unique_episodes_search=0
sonarr_unique_series_search=0

# --- Clear failed downloads from NZBGet history ---
clear_nzbget_failed() {
  [[ "$CLEAR_NZBGET_FAILED" != "1" ]] && return 0
  local history_raw
  history_raw=$(_nzbget_rpc "reading NZBGet download history" '{"jsonrpc":"2.0","method":"history","params":[false],"id":1}') || return 1
  local age_seconds=0
  [[ "$CLEAR_NZBGET_AGE_DAYS" -gt 0 ]] && age_seconds=$((CLEAR_NZBGET_AGE_DAYS * 86400))
  local failed_ids
  if [[ "$age_seconds" -gt 0 ]]; then
    local now_ts
    now_ts=$(date +%s 2>/dev/null) || return 0
    failed_ids=$(jq -r --argjson age "$age_seconds" --argjson now "$now_ts" '.result[]? | select(.Status != null and (.Status | startswith("FAILURE")) and (.HistoryTime != null) and (($now - .HistoryTime) >= $age)) | .NZBID' <<< "$history_raw" 2>/dev/null) || return 0
  else
    failed_ids=$(jq -r '.result[]? | select(.Status != null and (.Status | startswith("FAILURE"))) | .NZBID' <<< "$history_raw" 2>/dev/null) || return 0
  fi
  failed_ids=$(echo "$failed_ids" | tr '\n' ' ' | xargs)
  [[ -z "$failed_ids" ]] && return 0
  local ids_json
  ids_json=$(echo "$failed_ids" | tr ' ' '\n' | grep -E '^[0-9]+$' | jq -R 'tonumber' | jq -s .)
  [[ "$ids_json" == "[]" || -z "$ids_json" ]] && return 0
  if [[ "$DRY_RUN" == "1" ]]; then
    local count
    count=$(echo "$failed_ids" | wc -w | tr -d ' ')
    log "NZBGet: [DRY-RUN] would clear $count failed download(s) from history (NZBIDs: $failed_ids)"
    return 0
  fi
  local edit_resp
  edit_resp=$(_nzbget_rpc "clearing failed downloads from NZBGet history" "{\"jsonrpc\":\"2.0\",\"method\":\"editqueue\",\"params\":[\"HistoryFinalDelete\",\"\",$ids_json],\"id\":1}") || return 1
  local count
  count=$(echo "$failed_ids" | wc -w | tr -d ' ')
  log "NZBGet: cleared $count failed download(s) from history"
  return 0
}

# Fetch *arr queue with pagination (handles >500 items)
# Usage: _arr_queue "Radarr" "$RADARR_URL" "$RADARR_API_KEY"
# Output: concatenated JSON records, one per line
_arr_queue() {
  local app="$1" base_url="$2" api_key="$3" page=1 records=""
  local arr_fix task
  case "$app" in
    Radarr) arr_fix="Check RADARR_URL and RADARR_API_KEY in this script." ;;
    Sonarr) arr_fix="Check SONARR_URL and SONARR_API_KEY in this script." ;;
    *) arr_fix="Check the URL and API key for ${app} in this script." ;;
  esac
  while true; do
    local resp code body curl_err
    task="reading the ${app} download queue"
    [[ "$page" -gt 1 ]] && task="${task} (page ${page})"
    curl_err=$(mktemp) || return 1
    resp=$(_curl -s -S -m "${CURL_TIMEOUT}" -w "\n%{http_code}" -H "X-Api-Key: ${api_key}" \
      -H "Accept: application/json" \
      "${base_url}/api/v3/queue?page=${page}&pageSize=${QUEUE_PAGE_SIZE}" 2>"$curl_err") || {
      _log_service_failure "$app" "$task" "$base_url" "" "" "$(tr '\n' ' ' <"$curl_err")" "$arr_fix"
      rm -f "$curl_err"
      return 1
    }
    rm -f "$curl_err"
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "200" ]] || ! jq -e . <<< "$body" &>/dev/null; then
      _log_service_failure "$app" "$task" "$base_url" "$code" "$body" "" "$arr_fix"
      return 1
    fi

    local count=0
    if jq -e '.records' <<< "$body" &>/dev/null; then
      count=$(jq -r '.records | length' <<< "$body" 2>/dev/null) || count=0
      [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]] && count=0
      records+=$(jq -c '.records[]?' <<< "$body" 2>/dev/null)
    elif [[ "$(jq -r 'type' <<< "$body" 2>/dev/null)" == "array" ]]; then
      count=$(jq -r 'length' <<< "$body" 2>/dev/null) || count=0
      [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]] && count=0
      records+=$(jq -c '.[]?' <<< "$body" 2>/dev/null)
    else
      log_err "${app} sent an unexpected response while reading the download queue. Check ${app} URL and API key in this script."
      return 1
    fi
    [[ "$count" -lt "$QUEUE_PAGE_SIZE" ]] && break
    ((page++))
  done
  [[ -n "$records" ]] && printf '%s\n' "$records"
  return 0
}

# --- Process Radarr ---
process_radarr() {
  [[ "$SKIP_RADARR" == "1" ]] && return 0
  _arr_verify_auth "Radarr" "$RADARR_URL" "$RADARR_API_KEY" || return 1
  [[ "$SAFE_EMPTY_QUEUE" == "1" && ${#nzbget_set[@]} -eq 0 ]] && { log "Radarr: skipped (SAFE_EMPTY_QUEUE, NZBGet queue empty)"; return 0; }
  local records
  records=$(_arr_queue "Radarr" "$RADARR_URL" "$RADARR_API_KEY") || return 1
  local to_remove movie_ids
  to_remove=""
  movie_ids=""
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    local proto did mid title qid
    proto=""; did=""; mid=""; title=""; qid=""
    IFS=$'\t' read -r proto did mid title qid <<< "$(radarr_queue_fields <<< "$rec")"
    [[ "$proto" != "usenet" || -z "$did" ]] && continue
    [[ -n "${nzbget_set[$did]:-}" ]] && continue
    ((radarr_stale_count++)) || true
    to_remove="$to_remove $qid"
    if [[ -n "$mid" ]]; then movie_ids="$movie_ids $mid"; fi
    if [[ "$DRY_RUN" == "1" ]]; then
      local bl_msg=""; [[ "$BLOCKLIST_ENABLED" == "1" ]] && bl_msg=" and blocklist"
      log_fmt "Radarr: [DRY-RUN] would remove%s '%s' (queueId=%s), would search movie %s" "${bl_msg}" "${title}" "${qid}" "${mid}"
    else
      local bl_msg=""; [[ "$BLOCKLIST_ENABLED" == "1" ]] && bl_msg=" and blocklist"
      log_fmt "Radarr: stale '%s' (downloadId=%s, queueId=%s) -> remove%s" "${title}" "${did}" "${qid}" "${bl_msg}"
    fi
  done <<< "$records"

  local unique_movies
  unique_movies=$(echo "$movie_ids" | tr ' ' '\n' | sort -nu | tr '\n' ',' | sed 's/,$//')
  if [[ -n "$unique_movies" ]]; then
    radarr_unique_movies_search=$(echo "$unique_movies" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    local to_remove_count
    to_remove_count=$(echo "$to_remove" | tr ' ' '\n' | grep -c '^[0-9]' 2>/dev/null || echo 0)
    log "Radarr: stale queue items: $radarr_stale_count; would remove: $to_remove_count; unique movies to search: $radarr_unique_movies_search"
    return 0
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    local blocklist_val="false"
    [[ "$BLOCKLIST_ENABLED" == "1" ]] && blocklist_val="true"
    local IFS=$' \t\n'
    read -ra qid_arr <<< "$to_remove"
    for qid in "${qid_arr[@]}"; do
      [[ -z "$qid" ]] && continue
      [[ "$MAX_REMOVALS_PER_RUN" -gt 0 && "$removals_count" -ge "$MAX_REMOVALS_PER_RUN" ]] && { log "Radarr: stopped (MAX_REMOVALS_PER_RUN=$MAX_REMOVALS_PER_RUN reached)"; break; }
      if _arr_queue_delete "Radarr" "$RADARR_URL" "$RADARR_API_KEY" "$qid" "$blocklist_val"; then
        ((removals_count++))
        ((radarr_removed_count++)) || true
        _rate_limit
      else
        ((radarr_remove_failures++)) || true
      fi
    done
    if [[ -n "$unique_movies" && "$TRIGGER_SEARCH" == "1" ]]; then
      local movies_arr
      IFS=',' read -ra movies_arr <<< "$unique_movies"
      local i chunk ids_json
      for ((i = 0; i < ${#movies_arr[@]}; i += SEARCH_IDS_CHUNK_SIZE)); do
        chunk=("${movies_arr[@]:i:SEARCH_IDS_CHUNK_SIZE}")
        ids_json=$(printf '%s\n' "${chunk[@]}" | jq -R 'select(length>0) | tonumber' | jq -s .)
        [[ "$ids_json" == "[]" ]] && continue
        _arr_command_post "Radarr" "$RADARR_URL" "$RADARR_API_KEY" "{\"name\":\"MoviesSearch\",\"movieIds\":$ids_json}" "searching for replacement movies (batch $((i / SEARCH_IDS_CHUNK_SIZE + 1)))" || true
      done
    fi
  fi
  return 0
}

# --- Process Sonarr ---
process_sonarr() {
  [[ "$SKIP_SONARR" == "1" ]] && return 0
  _arr_verify_auth "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" || return 1
  [[ "$SAFE_EMPTY_QUEUE" == "1" && ${#nzbget_set[@]} -eq 0 ]] && { log "Sonarr: skipped (SAFE_EMPTY_QUEUE, NZBGet queue empty)"; return 0; }
  local records
  records=$(_arr_queue "Sonarr" "$SONARR_URL" "$SONARR_API_KEY") || return 1
  local to_remove episode_ids series_ids
  to_remove=""
  episode_ids=""
  series_ids=""
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    local proto did title qid episode_ids_csv sid
    proto=""; did=""; title=""; qid=""; episode_ids_csv=""; sid=""
    IFS=$'\t' read -r proto did title qid episode_ids_csv sid <<< "$(sonarr_queue_fields <<< "$rec")"
    [[ "$proto" != "usenet" || -z "$did" ]] && continue
    [[ -n "${nzbget_set[$did]:-}" ]] && continue
    ((sonarr_stale_count++)) || true
    to_remove="$to_remove $qid"
    if [[ -n "$episode_ids_csv" ]]; then
      episode_ids+=" ${episode_ids_csv//,/ }"
    fi
    [[ -n "$sid" && "$sid" != "null" ]] && series_ids="$series_ids $sid"
    if [[ "$DRY_RUN" == "1" ]]; then
      local bl_msg=""; [[ "$BLOCKLIST_ENABLED" == "1" ]] && bl_msg=" and blocklist"
      log_fmt "Sonarr: [DRY-RUN] would remove%s '%s' (queueId=%s)" "${bl_msg}" "${title}" "${qid}"
    else
      local bl_msg=""; [[ "$BLOCKLIST_ENABLED" == "1" ]] && bl_msg=" and blocklist"
      log_fmt "Sonarr: stale '%s' (downloadId=%s, queueId=%s) -> remove%s" "${title}" "${did}" "${qid}" "${bl_msg}"
    fi
  done <<< "$records"

  local unique_episodes unique_series
  unique_episodes=$(echo "$episode_ids" | tr ' ' '\n' | sort -nu | tr '\n' ',' | sed 's/,$//')
  unique_series=$(echo "$series_ids" | tr ' ' '\n' | sort -nu | tr '\n' ',' | sed 's/,$//')
  if [[ -n "$unique_episodes" ]]; then
    sonarr_unique_episodes_search=$(echo "$unique_episodes" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)
  fi
  if [[ -n "$unique_series" ]]; then
    sonarr_unique_series_search=$(echo "$unique_series" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    local to_remove_count
    to_remove_count=$(echo "$to_remove" | tr ' ' '\n' | grep -c '^[0-9]' 2>/dev/null || echo 0)
    log "Sonarr: stale queue items: $sonarr_stale_count; would remove: $to_remove_count; unique episodes to search: $sonarr_unique_episodes_search; unique series fallback: $sonarr_unique_series_search"
    return 0
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    local blocklist_val="false"
    [[ "$BLOCKLIST_ENABLED" == "1" ]] && blocklist_val="true"
    local IFS=$' \t\n'
    read -ra qid_arr <<< "$to_remove"
    for qid in "${qid_arr[@]}"; do
      [[ -z "$qid" ]] && continue
      [[ "$MAX_REMOVALS_PER_RUN" -gt 0 && "$removals_count" -ge "$MAX_REMOVALS_PER_RUN" ]] && { log "Sonarr: stopped (MAX_REMOVALS_PER_RUN=$MAX_REMOVALS_PER_RUN reached)"; break; }
      if _arr_queue_delete "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "$qid" "$blocklist_val"; then
        ((removals_count++))
        ((sonarr_removed_count++)) || true
        _rate_limit
      else
        ((sonarr_remove_failures++)) || true
      fi
    done
    if [[ "$TRIGGER_SEARCH" == "1" ]]; then
      if [[ -n "$unique_episodes" ]]; then
        local episodes_arr
        IFS=',' read -ra episodes_arr <<< "$unique_episodes"
        local i chunk ids_json
        for ((i = 0; i < ${#episodes_arr[@]}; i += SEARCH_IDS_CHUNK_SIZE)); do
          chunk=("${episodes_arr[@]:i:SEARCH_IDS_CHUNK_SIZE}")
          ids_json=$(printf '%s\n' "${chunk[@]}" | jq -R 'select(length>0) | tonumber' | jq -s .)
          [[ "$ids_json" == "[]" ]] && continue
          _arr_command_post "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "{\"name\":\"EpisodeSearch\",\"episodeIds\":$ids_json}" "searching for replacement episodes (batch $((i / SEARCH_IDS_CHUNK_SIZE + 1)))" || true
        done
      elif [[ -n "$unique_series" ]]; then
        IFS=',' read -ra sid_arr <<< "$unique_series"
        for sid in "${sid_arr[@]}"; do
          [[ -z "$sid" ]] && continue
          _arr_command_post "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "{\"name\":\"SeriesSearch\",\"seriesId\":$sid}" "searching series ${sid} for replacements" || true
        done
      fi
    fi
  fi
  return 0
}

# --- Main ---
exit_code=0
log "Queue sync start (NZBGet queue has $(printf '%s' "$nzbget_ids" | grep -c . 2>/dev/null || echo 0) item(s))"
[[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no removals or searches will be performed"
clear_nzbget_failed || exit_code=1
process_radarr || exit_code=1
process_sonarr || exit_code=1
log "Queue sync summary: Radarr stale=$radarr_stale_count removed=$radarr_removed_count remove_failures=$radarr_remove_failures unique_movies_to_search=$radarr_unique_movies_search | Sonarr stale=$sonarr_stale_count removed=$sonarr_removed_count remove_failures=$sonarr_remove_failures unique_episodes_to_search=$sonarr_unique_episodes_search unique_series_fallback=$sonarr_unique_series_search | dry_run=$DRY_RUN"
if [[ "$exit_code" -ne 0 ]]; then
  log_err "Queue sync finished with errors — see the ERROR lines above for what to fix."
  exit 1
fi
log "Queue sync done"
