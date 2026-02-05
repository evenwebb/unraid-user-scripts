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
#   ./queue-sync-nzbget.sh                    # Run with defaults
#   DRY_RUN=1 ./queue-sync-nzbget.sh          # Dry run (no removals or searches)
#
# Configuration:
#   Set URLs and API keys below or via environment variables (RADARR_URL, RADARR_API_KEY,
#   SONARR_URL, SONARR_API_KEY, NZBGET_URL, NZBGET_USER, NZBGET_PASS).
#   Leave a URL or API key empty to skip that app.
#
# Requires: curl, jq
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# --- Radarr ---
RADARR_URL=""           # e.g. http://192.168.1.10:7878 (no trailing slash)
RADARR_API_KEY=""   # Settings → General → API Key

# --- Sonarr ---
SONARR_URL=""           # e.g. http://192.168.1.10:8989 (no trailing slash)
SONARR_API_KEY=""   # Settings → General → API Key

# --- NZBGet ---
NZBGET_URL=""           # e.g. http://192.168.1.10:6789 (no trailing slash)
NZBGET_USER="nzbget"   # ControlUsername
NZBGET_PASS=""         # ControlPassword

# --- Behaviour ---
DRY_RUN="0"                # 1 = log only, no removals or searches
TRIGGER_SEARCH="1"  # 0 = remove+blocklist only
LOG_FILE=""               # If set, append logs here (e.g. /boot/config/queue-sync.log)
CURL_TIMEOUT="30"
SEARCH_IDS_CHUNK_SIZE="50"  # Max IDs per MoviesSearch/EpisodeSearch request

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

# Call *arr command API; on failure log HTTP status and response body (for debugging).
# Usage: _arr_command_post "Radarr" "$RADARR_URL" "$RADARR_API_KEY" '{"name":"MoviesSearch","movieIds":[1]}' "MoviesSearch (chunk 1)"
# Logs success message and returns 0, or logs error (with status/body) and returns 1.
_arr_command_post() {
    local app="$1" base_url="$2" api_key="$3" json_body="$4" label="$5"
    local resp code body
    resp=$(curl -s -S -m "${CURL_TIMEOUT}" -w "\n%{http_code}" -X POST \
      -H "X-Api-Key: ${api_key}" -H "Content-Type: application/json" \
      -d "$json_body" "${base_url}/api/v3/command") || { log_err "${app} ${label}: request failed (curl error)"; return 1; }
    code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')
    if [[ "$code" != "2"* ]]; then
      [[ -n "$body" ]] && body=" — ${body:0:400}" || body=""
      log_err "${app} ${label}: HTTP ${code}${body}"
      return 1
    fi
    log "${app}: triggered ${label}"
    return 0
}

# --- Fetch NZBGet queue IDs ---
nzbget_ids_raw=$(curl -s -S -m "${CURL_TIMEOUT}" -u "${NZBGET_USER}:${NZBGET_PASS}" -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"listgroups","params":[0],"id":1}' \
  "${NZBGET_JSONRPC}") || { log_err "NZBGet request failed"; exit 1; }

if ! nzbget_ids=$(jq -r '.result[]?.NZBID // empty' <<< "$nzbget_ids_raw" 2>/dev/null); then
  if jq -e '.error' <<< "$nzbget_ids_raw" &>/dev/null; then
    log_err "NZBGet API error: $(jq -r '.error.message // .error' <<< "$nzbget_ids_raw")"
  else
    log_err "NZBGet returned invalid JSON or no result array"
  fi
  exit 1
fi

nzbget_ids_list=$(echo "$nzbget_ids" | tr '\n' ' ')
read -ra nzbget_arr <<< "$nzbget_ids_list"

# --- Process Radarr ---
process_radarr() {
  [[ -z "$RADARR_URL" || -z "$RADARR_API_KEY" ]] && return 0
  local queue_json
  queue_json=$(curl -s -S -m "${CURL_TIMEOUT}" -H "X-Api-Key: ${RADARR_API_KEY}" \
    "${RADARR_URL}/api/v3/queue?pageSize=500") || { log_err "Radarr queue request failed"; return 1; }
  local records
  records=$(jq -c '.records[]?' <<< "$queue_json" 2>/dev/null) || return 0
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
    local found=0
    for nid in "${nzbget_arr[@]}"; do
      if [[ "$nid" == "$did" ]]; then found=1; break; fi
    done
    [[ $found -eq 1 ]] && continue
    local qid
    qid=$(jq -r '.id' <<< "$rec")
    to_remove="$to_remove $qid"
    if [[ -n "$mid" ]]; then movie_ids="$movie_ids $mid"; fi
    if [[ "$DRY_RUN" == "1" ]]; then
      log "Radarr: [DRY-RUN] would remove and blocklist '$title' (queueId=$qid), would search movie $mid"
    else
      log "Radarr: stale '$title' (downloadId=$did, queueId=$qid) -> remove and blocklist"
    fi
  done <<< "$records"

  if [[ "$DRY_RUN" != "1" ]]; then
    read -ra qid_arr <<< "$to_remove"
    for qid in "${qid_arr[@]}"; do
      [[ -z "$qid" ]] && continue
      curl -s -S -m "${CURL_TIMEOUT}" -X DELETE -H "X-Api-Key: ${RADARR_API_KEY}" \
        "${RADARR_URL}/api/v3/queue/${qid}?removeFromClient=true&blocklist=true" >/dev/null 2>&1 || log_err "Radarr DELETE queue $qid failed"
    done
    local unique_movies
    unique_movies=$(echo "$movie_ids" | tr ' ' '\n' | sort -nu | tr '\n' ',' | sed 's/,$//')
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
  [[ -z "$SONARR_URL" || -z "$SONARR_API_KEY" ]] && return 0
  local queue_json
  queue_json=$(curl -s -S -m "${CURL_TIMEOUT}" -H "X-Api-Key: ${SONARR_API_KEY}" \
    "${SONARR_URL}/api/v3/queue?pageSize=500") || { log_err "Sonarr queue request failed"; return 1; }
  local records
  records=$(jq -c '.records[]?' <<< "$queue_json" 2>/dev/null) || return 0
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
    local found=0
    for nid in "${nzbget_arr[@]}"; do
      if [[ "$nid" == "$did" ]]; then found=1; break; fi
    done
    [[ $found -eq 1 ]] && continue
    local qid
    qid=$(jq -r '.id' <<< "$rec")
    to_remove="$to_remove $qid"
    while read -r eid; do
      [[ -n "$eid" && "$eid" != "null" ]] && episode_ids="$episode_ids $eid"
    done < <(jq -r '(.episodeId // empty), (.episode.id // empty), (.episode.episodeId // empty), (.episodes[]?.id // empty), (.episodes[]?.episodeId // empty)' <<< "$rec")
    local sid
    sid=$(jq -r '.seriesId // .series?.id // empty' <<< "$rec")
    [[ -n "$sid" && "$sid" != "null" ]] && series_ids="$series_ids $sid"
    if [[ "$DRY_RUN" == "1" ]]; then
      log "Sonarr: [DRY-RUN] would remove and blocklist '$title' (queueId=$qid)"
    else
      log "Sonarr: stale '$title' (downloadId=$did, queueId=$qid) -> remove and blocklist"
    fi
  done <<< "$records"

  if [[ "$DRY_RUN" != "1" ]]; then
    read -ra qid_arr <<< "$to_remove"
    for qid in "${qid_arr[@]}"; do
      [[ -z "$qid" ]] && continue
      curl -s -S -m "${CURL_TIMEOUT}" -X DELETE -H "X-Api-Key: ${SONARR_API_KEY}" \
        "${SONARR_URL}/api/v3/queue/${qid}?removeFromClient=true&blocklist=true" >/dev/null 2>&1 || log_err "Sonarr DELETE queue $qid failed"
    done
    local unique_episodes unique_series
    unique_episodes=$(echo "$episode_ids" | tr ' ' '\n' | sort -nu | tr '\n' ',' | sed 's/,$//')
    unique_series=$(echo "$series_ids" | tr ' ' '\n' | sort -nu | tr '\n' ',' | sed 's/,$//')
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
log "Queue sync start (NZBGet queue has $(echo "$nzbget_ids" | wc -l | tr -d ' ') item(s))"
[[ "$DRY_RUN" == "1" ]] && log "DRY-RUN: no removals or searches will be performed"
process_radarr
process_sonarr
log "Queue sync done"
