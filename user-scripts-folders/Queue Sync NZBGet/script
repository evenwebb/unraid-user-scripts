#!/bin/bash
#
# queue-sync-nzbget.sh
# Syncs Sonarr/Radarr queues with NZBGet: removes stale queue entries and triggers search
#
# Description:
#   Compares *arr queue (usenet items) with NZBGet's active queue. Removes *arr queue
#   entries when the download is no longer in NZBGet (failed/removed), blocklists the
#   release, and optionally triggers a search so *arr finds another release.
#
# Usage:
#   ./queue-sync-nzbget.sh                # Run with defaults
#   Edit config variables below to change behaviour.
#
# Configuration:
#   Set URLs and API keys below (RADARR_URL, RADARR_API_KEY, SONARR_URL, SONARR_API_KEY,
#   NZBGET_URL, NZBGET_USER, NZBGET_PASS). Leave a URL or API key empty to skip that app,
#   or use SKIP_RADARR=1 / SKIP_SONARR=1.
#
#   Behaviour:
#   - CLEAR_NZBGET_FAILED=1  Clear failed downloads from NZBGet history (default: 0)
#   - CLEAR_NZBGET_AGE_DAYS  Only clear failed history older than N days; 0 = all (default: 0)
#   - BLOCKLIST_ENABLED=1    Blocklist release when removing from *arr queue (default: 1)
#   - TRIGGER_SEARCH=1       Force search in Sonarr/Radarr after removal (default: 1)
#   - SKIP_RADARR=1          Skip Radarr processing (default: 0)
#   - SKIP_SONARR=1          Skip Sonarr processing (default: 0)
#   - SAFE_EMPTY_QUEUE=1    Skip *arr removals when NZBGet queue is empty (default: 0)
#   - LOCK_FILE=path         Prevent concurrent runs; empty = no lock (default: empty)
#   - MAX_REMOVALS_PER_RUN   Cap removal attempts per run; 0 = no limit (default: 0)
#   - RATE_LIMIT_DELAY       Seconds between API calls during removals/searches (default: 0)
#   - RETRY_COUNT            Retries for failed curl requests; 0 = no retries (default: 0)
#   - LOG_FILE               Append logs to file; parent directory must exist (default: empty)
#   - CURL_TIMEOUT           Timeout for curl requests in seconds (default: 30)
#   - SEARCH_IDS_CHUNK_SIZE   Max IDs per MoviesSearch/EpisodeSearch request (default: 50)
#   - QUEUE_PAGE_SIZE        *arr queue page size for pagination (default: 500)
#
# Requires: curl, jq
# Requires: flock (only if LOCK_FILE is set)
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

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

# Strip trailing slashes
RADARR_URL="${RADARR_URL%/}"
SONARR_URL="${SONARR_URL%/}"
NZBGET_URL="${NZBGET_URL%/}"
NZBGET_JSONRPC="${NZBGET_URL}/jsonrpc"

# Require at least NZBGet to be configured (script is NZBGet-centric)
if [[ -z "$NZBGET_URL" || -z "$NZBGET_PASS" ]]; then
    echo "Error: Set NZBGET_URL and NZBGET_PASS (and optionally RADARR_* / SONARR_*). See script header." >&2
    exit 1
fi
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not found." >&2
        exit 1
    fi
done

# Validate URLs (reject file://, relative paths, etc.)
for url_var in RADARR_URL SONARR_URL NZBGET_URL; do
    url_val="${!url_var}"
    [[ -z "$url_val" ]] && continue
    if [[ ! "$url_val" =~ ^https?:// ]]; then
        echo "Error: $url_var must start with http:// or https:// (got: $url_val)" >&2
        exit 1
    fi
done

# Validate LOG_FILE path (reject path traversal)
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid (reject path traversal or stdio)" >&2
    exit 1
fi

# Validate numeric config (prevent infinite loops)
if [[ ! "$SEARCH_IDS_CHUNK_SIZE" =~ ^[1-9][0-9]*$ ]] || [[ ! "$QUEUE_PAGE_SIZE" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: SEARCH_IDS_CHUNK_SIZE and QUEUE_PAGE_SIZE must be positive integers." >&2
    exit 1
fi
if [[ ! "$RETRY_COUNT" =~ ^[0-9]+$ ]] || [[ ! "$MAX_REMOVALS_PER_RUN" =~ ^[0-9]+$ ]] || [[ ! "$RATE_LIMIT_DELAY" =~ ^[0-9]+$ ]] || [[ ! "$CLEAR_NZBGET_AGE_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: RETRY_COUNT, MAX_REMOVALS_PER_RUN, RATE_LIMIT_DELAY, CLEAR_NZBGET_AGE_DAYS must be non-negative integers." >&2
    exit 1
fi

# Acquire lock if LOCK_FILE is set
if [[ -n "$LOCK_FILE" ]]; then
    if [[ "$LOCK_FILE" == *".."* || "$LOCK_FILE" == "-"* ]]; then
        echo "Error: LOCK_FILE path invalid." >&2
        exit 1
    fi
    lock_dir=$(dirname "$LOCK_FILE")
    if [[ -n "$lock_dir" && "$lock_dir" != "." && ! -d "$lock_dir" ]]; then
        echo "Error: LOCK_FILE parent directory does not exist: $lock_dir" >&2
        exit 1
    fi
    if ! command -v flock &>/dev/null; then
        echo "Error: flock is required when LOCK_FILE is set but not found." >&2
        exit 1
    fi
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        echo "Error: Another instance is running (lock: $LOCK_FILE). Exiting." >&2
        exit 1
    fi
fi

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

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

# Call *arr command API; on failure log HTTP status and response body (for debugging).
# Usage: _arr_command_post "Radarr" "$RADARR_URL" "$RADARR_API_KEY" '{"name":"MoviesSearch","movieIds":[1]}' "MoviesSearch (chunk 1)"
# Logs success message and returns 0, or logs error (with status/body) and returns 1.
_arr_command_post() {
    local app="$1" base_url="$2" api_key="$3" json_body="$4" label="$5"
    local resp code body
    resp=$(_curl -s -S -m "${CURL_TIMEOUT}" -w "\n%{http_code}" -X POST \
      -H "X-Api-Key: ${api_key}" -H "Content-Type: application/json" \
      -d "$json_body" "${base_url}/api/v3/command") || { log_err "${app} ${label}: request failed (curl error)"; return 1; }
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "2"* ]]; then
      [[ -n "$body" ]] && body=" - ${body:0:400}" || body=""
      log_err "${app} ${label}: HTTP ${code}${body}"
      return 1
    fi
    log "${app}: triggered ${label}"
    _rate_limit
    return 0
}

# --- Fetch NZBGet queue IDs ---
nzbget_ids_raw=$(_curl -s -S -m "${CURL_TIMEOUT}" -u "${NZBGET_USER}:${NZBGET_PASS}" -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"listgroups","params":[0],"id":1}' \
  "${NZBGET_JSONRPC}") || { log_err "NZBGet request failed"; exit 1; }

if jq -e '.error' <<< "$nzbget_ids_raw" &>/dev/null; then
  log_err "NZBGet API error: $(jq -r '.error.message // .error' <<< "$nzbget_ids_raw")"
  exit 1
fi
if [[ "$(jq -r '.result | type' <<< "$nzbget_ids_raw" 2>/dev/null)" != "array" ]]; then
  log_err "NZBGet returned invalid response (result is not an array)"
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
radarr_unique_movies_search=0
sonarr_unique_episodes_search=0
sonarr_unique_series_search=0

# --- Clear failed downloads from NZBGet history ---
clear_nzbget_failed() {
  [[ "$CLEAR_NZBGET_FAILED" != "1" ]] && return 0
  local history_raw
  history_raw=$(_curl -s -S -m "${CURL_TIMEOUT}" -u "${NZBGET_USER}:${NZBGET_PASS}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"history","params":[false],"id":1}' \
    "${NZBGET_JSONRPC}") || { log_err "NZBGet history request failed"; return 1; }
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
  edit_resp=$(_curl -s -S -m "${CURL_TIMEOUT}" -u "${NZBGET_USER}:${NZBGET_PASS}" -X POST \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"editqueue\",\"params\":[\"HistoryFinalDelete\",\"\",$ids_json],\"id\":1}" \
    "${NZBGET_JSONRPC}") || { log_err "NZBGet editqueue (HistoryFinalDelete) failed"; return 1; }
  if jq -e '.error' <<< "$edit_resp" &>/dev/null; then
    log_err "NZBGet API error: $(jq -r '.error.message // .error' <<< "$edit_resp")"
    return 1
  fi
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
  while true; do
    local resp
    resp=$(_curl -s -S -m "${CURL_TIMEOUT}" -H "X-Api-Key: ${api_key}" \
      "${base_url}/api/v3/queue?page=${page}&pageSize=${QUEUE_PAGE_SIZE}") || { log_err "${app} queue request failed"; return 1; }
    if ! jq -e '.records' <<< "$resp" &>/dev/null; then
      log_err "${app}: queue response invalid (missing .records)"
      return 1
    fi
    local count
    count=$(jq -r '.records | length' <<< "$resp" 2>/dev/null) || count=0
    [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]] && count=0
    records+=$(jq -c '.records[]?' <<< "$resp" 2>/dev/null)
    [[ "$count" -lt "$QUEUE_PAGE_SIZE" ]] && break
    ((page++))
  done
  [[ -n "$records" ]] && printf '%s\n' "$records"
  return 0
}

# --- Process Radarr ---
process_radarr() {
  [[ "$SKIP_RADARR" == "1" ]] && return 0
  [[ -z "$RADARR_URL" || -z "$RADARR_API_KEY" ]] && return 0
  [[ "$SAFE_EMPTY_QUEUE" == "1" && ${#nzbget_set[@]} -eq 0 ]] && { log "Radarr: skipped (SAFE_EMPTY_QUEUE, NZBGet queue empty)"; return 0; }
  local records
  records=$(_arr_queue "Radarr" "$RADARR_URL" "$RADARR_API_KEY") || return 1
  local to_remove movie_ids
  to_remove=""
  movie_ids=""
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    local proto did mid title
    proto=$(jq -r '.protocol // ""' <<< "$rec")
    did=$(jq -r '.downloadId // ""' <<< "$rec")
    mid=$(jq -r '.movieId // empty' <<< "$rec")
    title=$(jq -r '.title // "?"' <<< "$rec")
    [[ "$proto" != "usenet" || -z "$did" ]] && continue
    [[ -n "${nzbget_set[$did]:-}" ]] && continue
    ((radarr_stale_count++)) || true
    local qid
    qid=$(jq -r '.id' <<< "$rec")
    to_remove="$to_remove $qid"
    if [[ -n "$mid" ]]; then movie_ids="$movie_ids $mid"; fi
    local safe_title="${title//\$/\\$}"
    safe_title="${safe_title//\`/\\`}"
    if [[ "$DRY_RUN" == "1" ]]; then
      local bl_msg=""; [[ "$BLOCKLIST_ENABLED" == "1" ]] && bl_msg=" and blocklist"
      log "Radarr: [DRY-RUN] would remove${bl_msg} '$safe_title' (queueId=$qid), would search movie $mid"
    else
      local bl_msg=""; [[ "$BLOCKLIST_ENABLED" == "1" ]] && bl_msg=" and blocklist"
      log "Radarr: stale '$safe_title' (downloadId=$did, queueId=$qid) -> remove${bl_msg}"
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
      _curl -s -S -m "${CURL_TIMEOUT}" -X DELETE -H "X-Api-Key: ${RADARR_API_KEY}" \
        "${RADARR_URL}/api/v3/queue/${qid}?removeFromClient=true&blocklist=${blocklist_val}" >/dev/null 2>&1 || log_err "Radarr DELETE queue $qid failed"
      ((removals_count++))
      ((radarr_removed_count++)) || true
      _rate_limit
    done
    if [[ -n "$unique_movies" && "$TRIGGER_SEARCH" == "1" ]]; then
      local movies_arr
      IFS=',' read -ra movies_arr <<< "$unique_movies"
      local i chunk ids_json
      for ((i = 0; i < ${#movies_arr[@]}; i += SEARCH_IDS_CHUNK_SIZE)); do
        chunk=("${movies_arr[@]:i:SEARCH_IDS_CHUNK_SIZE}")
        ids_json=$(printf '%s\n' "${chunk[@]}" | jq -R 'select(length>0) | tonumber' | jq -s .)
        [[ "$ids_json" == "[]" ]] && continue
        _arr_command_post "Radarr" "$RADARR_URL" "$RADARR_API_KEY" "{\"name\":\"MoviesSearch\",\"movieIds\":$ids_json}" "MoviesSearch for movie(s) chunk $((i / SEARCH_IDS_CHUNK_SIZE + 1))" || true
      done
    fi
  fi
  return 0
}

# --- Process Sonarr ---
process_sonarr() {
  [[ "$SKIP_SONARR" == "1" ]] && return 0
  [[ -z "$SONARR_URL" || -z "$SONARR_API_KEY" ]] && return 0
  [[ "$SAFE_EMPTY_QUEUE" == "1" && ${#nzbget_set[@]} -eq 0 ]] && { log "Sonarr: skipped (SAFE_EMPTY_QUEUE, NZBGet queue empty)"; return 0; }
  local records
  records=$(_arr_queue "Sonarr" "$SONARR_URL" "$SONARR_API_KEY") || return 1
  local to_remove episode_ids series_ids
  to_remove=""
  episode_ids=""
  series_ids=""
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    local proto did title eid
    proto=$(jq -r '.protocol // ""' <<< "$rec")
    did=$(jq -r '.downloadId // ""' <<< "$rec")
    title=$(jq -r '.title // "?"' <<< "$rec")
    [[ "$proto" != "usenet" || -z "$did" ]] && continue
    [[ -n "${nzbget_set[$did]:-}" ]] && continue
    ((sonarr_stale_count++)) || true
    local qid
    qid=$(jq -r '.id' <<< "$rec")
    to_remove="$to_remove $qid"
    local safe_title="${title//\$/\\$}"
    safe_title="${safe_title//\`/\\`}"
    while read -r eid; do
      [[ -n "$eid" && "$eid" != "null" ]] && episode_ids="$episode_ids $eid"
    done < <(jq -r '(.episodeId // empty), (.episode.id // empty), (.episode.episodeId // empty), (.episodes[]?.id // empty), (.episodes[]?.episodeId // empty)' <<< "$rec")
    local sid
    sid=$(jq -r '.seriesId // .series?.id // empty' <<< "$rec")
    [[ -n "$sid" && "$sid" != "null" ]] && series_ids="$series_ids $sid"
    if [[ "$DRY_RUN" == "1" ]]; then
      local bl_msg=""; [[ "$BLOCKLIST_ENABLED" == "1" ]] && bl_msg=" and blocklist"
      log "Sonarr: [DRY-RUN] would remove${bl_msg} '$safe_title' (queueId=$qid)"
    else
      local bl_msg=""; [[ "$BLOCKLIST_ENABLED" == "1" ]] && bl_msg=" and blocklist"
      log "Sonarr: stale '$safe_title' (downloadId=$did, queueId=$qid) -> remove${bl_msg}"
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
      _curl -s -S -m "${CURL_TIMEOUT}" -X DELETE -H "X-Api-Key: ${SONARR_API_KEY}" \
        "${SONARR_URL}/api/v3/queue/${qid}?removeFromClient=true&blocklist=${blocklist_val}" >/dev/null 2>&1 || log_err "Sonarr DELETE queue $qid failed"
      ((removals_count++))
      ((sonarr_removed_count++)) || true
      _rate_limit
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
          _arr_command_post "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "{\"name\":\"EpisodeSearch\",\"episodeIds\":$ids_json}" "EpisodeSearch for episode(s) chunk $((i / SEARCH_IDS_CHUNK_SIZE + 1))" || true
        done
      elif [[ -n "$unique_series" ]]; then
        IFS=',' read -ra sid_arr <<< "$unique_series"
        for sid in "${sid_arr[@]}"; do
          [[ -z "$sid" ]] && continue
          _arr_command_post "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "{\"name\":\"SeriesSearch\",\"seriesId\":$sid}" "SeriesSearch for series $sid" || true
        done
      fi
    fi
  fi
  return 0
}

# --- Main ---
log "Queue sync start (NZBGet queue has $(printf '%s' "$nzbget_ids" | grep -c . 2>/dev/null || echo 0) item(s))"
[[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no removals or searches will be performed"
clear_nzbget_failed || true
process_radarr || log_err "Radarr processing failed"
process_sonarr || log_err "Sonarr processing failed"
log "Queue sync summary: Radarr stale=$radarr_stale_count removed=$radarr_removed_count unique_movies_to_search=$radarr_unique_movies_search | Sonarr stale=$sonarr_stale_count removed=$sonarr_removed_count unique_episodes_to_search=$sonarr_unique_episodes_search unique_series_fallback=$sonarr_unique_series_search | dry_run=$DRY_RUN"
log "Queue sync done"
