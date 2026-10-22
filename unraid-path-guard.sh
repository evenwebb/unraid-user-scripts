#!/bin/bash
#
# unraid-path-guard.sh
# Version: 1.0.0
# Monitor unexpected Unraid shares/folders and suspect Docker host paths.
# MONITOR-ONLY: sends alerts; never changes monitored directories or Docker.
#
# Description:
#   First run remembers existing user shares and /mnt directories. Later runs
#   detect new ones. Also audits saved Docker templates and all containers,
#   including stopped containers, for common storage path mistakes.
#   An explicitly forbidden appdata path is NEVER silently baselined.
#
# Usage:
#   Run in Settings > User Scripts, then schedule hourly or at array start.
#   Edit the settings below; they are compatible with this repo's updater.
#   bash script --accept-current   # approve today's top-level folders
#   bash script --help
#
# MONITOR-ONLY: no automatic deletion, repair, migration, or Docker changes.
# Writes ONLY its own baseline/alert state in STATE_DIR and optional logs.
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0
set -uo pipefail

###############################################################################
# EDIT FOR YOUR SETUP (monitoring and alert settings only)
###############################################################################

# --- Your storage layout ----------------------------------------------------
# Your dedicated appdata pool/disk and the preferred Docker data directory.
APPDATA_MOUNT="/mnt/appdata"
EXPECTED_APPDATA="/mnt/appdata/docker"
# Common Unraid template mistake: this creates an unintended appdata share.
FORBIDDEN_APPDATA="/mnt/user/appdata"

# --- What to check (1=enabled, 0=disabled) ---------------------------------
CHECK_NEW_SHARES="1"          # New top-level /mnt/user shares
CHECK_NEW_MNT_DIRS="1"        # Unexpected new directories directly in /mnt
CHECK_FORBIDDEN_PATHS="1"     # Any forbidden path exists OR Docker maps to it
CHECK_APPDATA_MOUNT="1"       # Expected pool/disk is mounted
CHECK_DOCKER="1"              # Inspect running AND stopped Docker containers
CHECK_DOCKER_TEMPLATES="1"    # Scan saved user templates from dockerMan
CHECK_TEMPLATE_DEFAULTS="1"  # Warn about a risky Default= (review only)
CHECK_BROAD_BIND_MOUNTS="1"   # Docker mapped to /mnt or /mnt/user etc.
CHECK_EMPTY_BIND_DIRS="1"     # Review empty mapped directories (can be normal)
CHECK_MISSING_BIND_DIRS="0"   # Off by default: templates often point to future folders
CHECK_UNMOUNTED_BIND_ROOTS="1" # /mnt/poolname does not appear to be mounted
CHECK_CUSTOM_WATCHES="1"     # New immediate child folders in custom locations
ALERT_MISSING_WATCH_ROOTS="0" # Optional: warn if custom watch root disappears

# --- Extra watches and exceptions -----------------------------------------
# Add extra absolute folders to warn about if they EXIST; mapped children of
# these paths also generate alerts. Example: "/mnt/user/docker-data".
# Note: FORBIDDEN_APPDATA is always included automatically.
CUSTOM_FORBIDDEN_PATHS=(
)

# Watch for newly-created IMMEDIATE SUBFOLDERS inside each directory below.
# Normal existing subfolders are remembered on the first run for each watch.
# Does not recursively scan every file in media libraries.
CUSTOM_WATCH_DIRS=(
    # "/mnt/user/downloads"
    # "/mnt/appdata/docker"
)

# Optional: complain if these absolute paths are missing (files or dirs).
CUSTOM_REQUIRED_PATHS=(
    # "/mnt/user/media"
)

# Explicitly approved NEW names to ignore in top-level share checks.
# Note: forbidden paths override these exceptions.
ALLOWED_NEW_SHARES=(
    # "My Intended New Share"
)
ALLOWED_NEW_MNT_DIRS=(
    # "temporaryfolder"
)

# --- Alerts and state -------------------------------------------------------
SEND_NOTIFICATIONS="1"
REMINDER_HOURS="24"           # Re-alert for unresolved findings after N hours; 0=each run
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"
LOG_FILE=""                   # Empty = log to User Scripts run window only
STATE_DIR="/boot/config/plugins/unraid-path-guard"
LOCK_FILE="/tmp/unraid-path-guard.lock"

# --- Advanced (usually leave these alone) ---------------------------------
MNT_ROOT="/mnt"
USER_ROOT="/mnt/user"
TEMPLATE_DIR="/boot/config/plugins/dockerMan/templates-user"
DOCKER_BIN="docker"
REQUIRE_USER_MOUNT="1"        # Avoid accepting empty shares when array is stopped
###############################################################################

usage() {
  cat <<'HELP'
Usage: bash unraid-path-guard.sh [--accept-current | --help]
  default:           check paths, report concerns, send due notifications
                     (monitor-only; no automatic cleanup or repairs)
  --accept-current:  accept all currently existing top-level shares, /mnt
                     directories, and configured custom watch subfolders
                     as new baselines. Forbidden paths ALWAYS remain warned.
  --help:            show this help
Edit the "EDIT FOR YOUR SETUP" section for settings and custom watches.
HELP
}
case "${1:-}" in
  ''|--accept-current) ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

log() { local msg="[$(date '+%Y-%m-%d %H:%M:%S')] Path Guard: $*"; printf '%s\n' "$msg"; if [[ -n "$LOG_FILE" ]] && ! printf '%s\n' "$msg" >> "$LOG_FILE"; then printf '%s\n' "Path Guard: cannot append to LOG_FILE: $LOG_FILE" >&2; fi; }
log_error() { log "ERROR: $*" >&2; }
under_path() { local item="$1" root="$2"; while [[ "$item" != / && "$item" == */ ]]; do item="${item%/}"; done; while [[ "$root" != / && "$root" == */ ]]; do root="${root%/}"; done; [[ "$item" == "$root" || "$item" == "$root/"* ]]; }
valid_path() { [[ "$1" == /* && "$1" != *$'\n'* && "$1" != *$'\r'* && "$1" != *$'\t'* && "$1" != *'/../'* && "$1" != */.. && "$1" != *'/./'* && "$1" != */. ]]; }
allowed_name() { local needle="$1"; shift; local v; for v in "$@"; do [[ "$v" == "$needle" ]] && return 0; done; return 1; }
has_entries() { [[ -n "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; }

for p in "$MNT_ROOT" "$USER_ROOT" "$APPDATA_MOUNT" "$EXPECTED_APPDATA" "$FORBIDDEN_APPDATA" "$TEMPLATE_DIR" "$STATE_DIR"; do
  valid_path "$p" && [[ "$p" != / ]] || { log_error "Invalid configuration path: $p"; exit 2; }
done
for p in "${CUSTOM_FORBIDDEN_PATHS[@]}" "${CUSTOM_WATCH_DIRS[@]}" "${CUSTOM_REQUIRED_PATHS[@]}"; do
  valid_path "$p" && [[ "$p" != / ]] || { log_error "Invalid custom path: $p"; exit 2; }
done
for p in "$LOG_FILE" "$NOTIFY_SCRIPT" "$LOCK_FILE"; do
  [[ -z "$p" ]] && continue
  valid_path "$p" || { log_error "Invalid configured file path: $p"; exit 2; }
done
[[ "$STATE_DIR" != /mnt && "$STATE_DIR" != /mnt/* ]] || { log_error 'STATE_DIR must be outside /mnt (use the flash drive)'; exit 2; }
[[ "$REMINDER_HOURS" =~ ^[0-9]+$ ]] || { log_error 'REMINDER_HOURS must be a non-negative integer'; exit 2; }
for flag in "$CHECK_NEW_SHARES" "$CHECK_NEW_MNT_DIRS" "$CHECK_FORBIDDEN_PATHS" "$CHECK_APPDATA_MOUNT" "$CHECK_DOCKER" "$CHECK_DOCKER_TEMPLATES" "$CHECK_TEMPLATE_DEFAULTS" "$CHECK_BROAD_BIND_MOUNTS" "$CHECK_EMPTY_BIND_DIRS" "$CHECK_MISSING_BIND_DIRS" "$CHECK_UNMOUNTED_BIND_ROOTS" "$CHECK_CUSTOM_WATCHES" "$ALERT_MISSING_WATCH_ROOTS" "$SEND_NOTIFICATIONS" "$REQUIRE_USER_MOUNT"; do
  [[ "$flag" == 0 || "$flag" == 1 ]] || { log_error "Boolean settings must be 0 or 1 (got: $flag)"; exit 2; }
done
for watch in "${CUSTOM_WATCH_DIRS[@]}"; do
  if under_path "$watch" "$STATE_DIR" || under_path "$STATE_DIR" "$watch"; then
    log_error "CUSTOM_WATCH_DIRS cannot overlap STATE_DIR: $watch"
    exit 2
  fi
done
[[ "$MNT_ROOT" != / && "$USER_ROOT" != / ]] || { log_error 'Storage roots cannot be /'; exit 2; }

# Never baseline empty /mnt/user while the array is offline.
if [[ ! -d "$USER_ROOT" ]] || { [[ "$REQUIRE_USER_MOUNT" == 1 ]] && ! mountpoint -q -- "$USER_ROOT"; }; then
  log_error "$USER_ROOT isn't available/mounted. Start the array before scanning."
  exit 1
fi
mkdir -p -- "$STATE_DIR" || { log_error "Cannot create $STATE_DIR"; exit 1; }
state_real=$(cd -P "$STATE_DIR" 2>/dev/null && pwd -P) || { log_error "Cannot resolve state directory: $STATE_DIR"; exit 1; }
mnt_real=$(cd -P "$MNT_ROOT" 2>/dev/null && pwd -P) || mnt_real="$MNT_ROOT"
if under_path "$state_real" /mnt || under_path "$state_real" "$mnt_real"; then
  log_error "Resolved STATE_DIR must stay outside /mnt and MNT_ROOT: $state_real"
  exit 2
fi
chmod 700 "$STATE_DIR" 2>/dev/null || { log_error "Cannot secure state directory: $STATE_DIR"; exit 1; }
if [[ -n "$LOCK_FILE" ]]; then
  if command -v flock >/dev/null 2>&1; then
    exec 9>> "$LOCK_FILE" || { log_error "Cannot open lock file: $LOCK_FILE"; exit 1; }
    flock -n 9 || { log 'Another scan is already running; skipping.'; exit 0; }
  else
    log 'flock unavailable; proceeding without overlap protection.'
  fi
fi

# Root directory is enumerated one level deep, including hidden folders.
list_directories() {
  local root="$1" dir
  [[ -d "$root" ]] || return 0
  for dir in "$root"/* "$root"/.[!.]* "$root"/..?*; do
    [[ -d "$dir" || -L "$dir" ]] || continue
    if [[ "${dir##*/}" == *$'\n'* || "${dir##*/}" == *$'\t'* ]]; then
      log "WARNING: skipped directory name containing a newline or tab under $root." >&2
      continue
    fi
    printf '%s\n' "${dir##*/}"
  done | LC_ALL=C sort -u
}
list_mnt_unmounted() {
  local name path
  while IFS= read -r name; do
    case "$name" in
      user|user0|disks|remotes|addons|rootshare) continue ;;
    esac
    [[ "$name" =~ ^disk[0-9]+$ ]] && continue
    path="$MNT_ROOT/$name"
    mountpoint -q -- "$path" 2>/dev/null && continue
    printf '%s\n' "$name"
  done < <(list_directories "$MNT_ROOT")
}
write_snapshot() {
  local target="$1" tmp
  tmp=$(mktemp "$STATE_DIR/.snapshot.XXXXXXXX") || return 1
  cat > "$tmp" || { rm -f -- "$tmp"; return 1; }
  if [[ -f "$target" ]] && cmp -s -- "$target" "$tmp"; then
    rm -f -- "$tmp"
  else
    mv -f -- "$tmp" "$target" || { rm -f -- "$tmp"; return 1; }
  fi
}

SHARE_BASELINE="$STATE_DIR/shares.baseline"
MNT_BASELINE="$STATE_DIR/mnt.baseline"
ALERT_STATE="$STATE_DIR/alerts.state"
ACCEPT_CURRENT="0"
[[ "${1:-}" == --accept-current ]] && ACCEPT_CURRENT=1

# Monitor top-level shares. Baselines are not auto-expanded: new shares keep
# alerting until they are removed or explicitly accepted.
check_new_items() {
  local label="$1" root="$2" baseline="$3" mode="$4" entry
  local -a items=()
  if [[ "$mode" == mnt ]]; then
    mapfile -t items < <(list_mnt_unmounted)
  else
    mapfile -t items < <(list_directories "$root")
  fi
  if [[ "$ACCEPT_CURRENT" == 1 || ! -f "$baseline" ]]; then
    printf '%s\n' "${items[@]}" | sed '/^$/d' | write_snapshot "$baseline" || return 1
    log "$label: baseline $((${#items[@]})) folder(s) ($( [[ "$ACCEPT_CURRENT" == 1 ]] && echo accepted || echo initial ))."
    return 0
  fi
  for entry in "${items[@]}"; do
    grep -Fxq -- "$entry" "$baseline" && continue
    if [[ "$mode" == shares ]] && allowed_name "$entry" "${ALLOWED_NEW_SHARES[@]}"; then continue; fi
    if [[ "$mode" == mnt ]] && allowed_name "$entry" "${ALLOWED_NEW_MNT_DIRS[@]}"; then continue; fi
    add_issue warning "NEW $label: $root/$entry (not in the accepted baseline)"
  done
}

declare -A ISSUE_TEXT=()
declare -A ISSUE_LEVEL=()
declare -A LAST_NOTIFIED=()
add_issue() {
  local level="$1" issue="$2" id
  id=$(printf '%s' "$issue" | sha256sum | cut -d' ' -f1)
  ISSUE_TEXT["$id"]="$issue"
  ISSUE_LEVEL["$id"]="$level"
}

# First-run baseline only skips generic "new folder" findings. The explicit
# forbidden path and wrong Docker mappings are ALWAYS checked on first run.
if [[ "$CHECK_NEW_SHARES" == 1 ]]; then
  check_new_items 'SHARE' "$USER_ROOT" "$SHARE_BASELINE" shares || exit 1
fi
if [[ "$CHECK_NEW_MNT_DIRS" == 1 ]]; then
  check_new_items '/mnt DIRECTORY' "$MNT_ROOT" "$MNT_BASELINE" mnt || exit 1
fi

if [[ "$CHECK_CUSTOM_WATCHES" == 1 ]]; then
  for watch in "${CUSTOM_WATCH_DIRS[@]}"; do
    if [[ ! -d "$watch" ]]; then
      if [[ "$ALERT_MISSING_WATCH_ROOTS" == 1 ]]; then
        add_issue warning "WATCH FOLDER MISSING: $watch"
      else
        log "Custom watch isn't accessible: $watch; skipped."
      fi
      continue
    fi
    watch_id=$(printf %s "$watch" | sha256sum | cut -c1-20)
    check_new_items 'WATCHED SUBFOLDER' "$watch" "$STATE_DIR/watch-$watch_id.baseline" watch || exit 1
  done
fi

if [[ "$CHECK_FORBIDDEN_PATHS" == 1 ]]; then
  for forbidden in "$FORBIDDEN_APPDATA" "${CUSTOM_FORBIDDEN_PATHS[@]}"; do
    if [[ -e "$forbidden" || -L "$forbidden" ]]; then
      add_issue alert "FORBIDDEN PATH EXISTS: $forbidden (expected appdata: $EXPECTED_APPDATA). Investigate this path manually."
    fi
  done
fi

if [[ "$CHECK_APPDATA_MOUNT" == 1 ]]; then
  if [[ ! -d "$APPDATA_MOUNT" ]]; then
    add_issue alert "APPDATA POOL MISSING: $APPDATA_MOUNT. Docker may write to the wrong filesystem."
  elif ! mountpoint -q -- "$APPDATA_MOUNT"; then
    add_issue alert "APPDATA POOL NOT MOUNTED: $APPDATA_MOUNT. Do not trust bind mappings until storage is available."
  elif [[ ! -d "$EXPECTED_APPDATA" ]]; then
    add_issue warning "APPDATA DIRECTORY MISSING: $EXPECTED_APPDATA. Check expected appdata layout."
  fi
fi
for required in "${CUSTOM_REQUIRED_PATHS[@]}"; do
  if [[ ! -e "$required" && ! -L "$required" ]]; then
    add_issue warning "REQUIRED PATH MISSING: $required"
  fi
done

# A mapping can exist and still be wrong: detect path prefixes regardless of
# whether Docker has already created the directory on disk.
check_host_path() {
  local origin="$1" path="$2" target="${3:-}" kind="${4:-selected}"
  while [[ "$path" != / && "$path" == */ ]]; do path="${path%/}"; done
  local label="$origin: $path${target:+ -> $target}" forbidden remainder top
  [[ "$path" == /* ]] || return 0
  if [[ "$path" == *'/../'* || "$path" == */.. || "$path" == *'/./'* ]]; then
    add_issue warning "NON-CANONICAL DOCKER HOST PATH: $label. Review path traversal components."
  fi
  if [[ "$CHECK_FORBIDDEN_PATHS" == 1 ]]; then
    for forbidden in "$FORBIDDEN_APPDATA" "${CUSTOM_FORBIDDEN_PATHS[@]}"; do
      if under_path "$path" "$forbidden"; then
        if [[ "$kind" == default ]]; then
          [[ "$CHECK_TEMPLATE_DEFAULTS" == 1 ]] && add_issue warning "TEMPLATE DEFAULT TO REVIEW: $label suggests forbidden $forbidden. Verify actual mapping when installing."
        else
          add_issue alert "FORBIDDEN DOCKER HOST PATH: $label (use $EXPECTED_APPDATA for appdata)."
        fi
      fi
    done
  fi
  [[ "$kind" == default ]] && return 0 # Defaults may be replaced by Unraid automatically.
  if [[ "$CHECK_BROAD_BIND_MOUNTS" == 1 ]]; then
    case "$path" in
      /|"$MNT_ROOT"|"$USER_ROOT"|"$APPDATA_MOUNT") add_issue warning "BROAD DOCKER BIND: $label. Confirm root-level access is intentional." ;;
    esac
  fi
  if [[ "$CHECK_UNMOUNTED_BIND_ROOTS" == 1 ]] && [[ "$path" != "$MNT_ROOT" ]] && under_path "$path" "$MNT_ROOT" && ! under_path "$path" "$USER_ROOT"; then
    remainder="${path#"$MNT_ROOT"/}"
    top="${remainder%%/*}"
    case "$top" in
      ''|user|user0|disks|remotes|addons|rootshare) ;;
      *)
        if [[ ! "$top" =~ ^disk[0-9]+$ ]] && ! mountpoint -q -- "$MNT_ROOT/$top" 2>/dev/null; then
          add_issue alert "DOCKER BIND UNDER UNMOUNTED ROOT: $label. Check $MNT_ROOT/$top for a typo or unavailable pool."
        fi
        ;;
    esac
  fi
  if [[ "$CHECK_MISSING_BIND_DIRS" == 1 ]] && under_path "$path" "$MNT_ROOT" && [[ ! -e "$path" && ! -L "$path" ]]; then
    add_issue warning "MISSING DOCKER HOST PATH: $label. Docker may create it automatically."
  fi
  if [[ "$CHECK_EMPTY_BIND_DIRS" == 1 ]] && under_path "$path" "$MNT_ROOT" && [[ -d "$path" ]] && ! has_entries "$path"; then
    add_issue warning "EMPTY DOCKER HOST DIRECTORY: $label. This can be normal for a new application."
  fi
}

# Includes stopped containers; no operations change Docker configuration.
if [[ "$CHECK_DOCKER" == 1 ]]; then
  if command -v "$DOCKER_BIN" >/dev/null 2>&1 && "$DOCKER_BIN" info >/dev/null 2>&1; then
    if container_listing=$("$DOCKER_BIN" ps -aq 2>/dev/null); then
      mapfile -t containers <<< "$container_listing"
    else
      log 'WARNING: Docker container listing failed; container inspection skipped.'
      containers=()
    fi
    for container in "${containers[@]}"; do
      [[ -n "$container" ]] || continue
      inspected=$("$DOCKER_BIN" inspect --format '{{.Name}}{{println}}{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{printf "\t"}}{{.Destination}}{{println}}{{end}}{{end}}' "$container" 2>/dev/null) || { log "Unable to inspect Docker container $container"; continue; }
      container_name="${inspected%%$'\n'*}"
      container_name="${container_name#/}"
      while IFS=$'\t' read -r path dest; do
        [[ -n "$path" ]] && check_host_path "Container $container_name" "$path" "$dest" selected
      done <<< "${inspected#*$'\n'}"
    done
  else
    log 'Docker is unavailable/stopped, skipping container inspection; XML templates are still checked.'
  fi
fi

# Unraid saved templates (v2 Config Type=Path and legacy HostDir).
# Prefer selected Value= or body text over Default=. Never report an unused
# Default= as a confirmed mapping; label those for review only.
if [[ "$CHECK_DOCKER_TEMPLATES" == 1 && -d "$TEMPLATE_DIR" ]]; then
  if command -v php >/dev/null 2>&1; then
    php_code=$(cat <<'PHP'
$dir = $argv[1];
if (!function_exists('simplexml_load_file')) {
  echo "__WARNING__\tPHP SimpleXML extension unavailable\twarning\n";
  exit(0);
}
foreach (glob(rtrim($dir, "/") . "/*.xml") ?: [] as $file) {
  libxml_clear_errors();
  $xml = @simplexml_load_file($file, 'SimpleXMLElement', LIBXML_NONET);
  if ($xml === false) {
    echo "__WARNING__\tInvalid XML template: ".str_replace(["\n","\t"]," ",basename($file))."\twarning\n";
    continue;
  }
  $container = basename($file, ".xml");
  $names = $xml->xpath('//Name');
  if ($names && trim((string)$names[0]) !== '') $container = trim((string)$names[0]);
  foreach ($xml->xpath('//Config') ?: [] as $config) {
    $a=[];
    foreach ($config->attributes() as $key=>$value) $a[strtolower((string)$key)] = (string)$value;
    if (strtolower($a['type']??'') !== 'path') continue;
    $body = trim((string)$config);
    if (($a['value']??'') !== '') { $chosen=$a['value']; $kind='selected'; }
    elseif ($body !== '') { $chosen=$body; $kind='selected'; }
    else { $chosen=$a['default']??''; $kind='default'; }
    if ($chosen !== '') echo str_replace(["\n","\t"]," ",$container)."\t".str_replace(["\n","\t"]," ",$chosen)."\t".$kind."\n";
  }
  foreach ($xml->xpath('//HostDir') ?: [] as $host_dir) {
    $host=trim((string)$host_dir);
    if ($host !== '') echo str_replace(["\n","\t"]," ",$container)."\t".str_replace(["\n","\t"]," ",$host)."\tselected\n";
  }
}
PHP
)
    template_listing=$(php -r "$php_code" "$TEMPLATE_DIR" 2>&1)
    if [[ $? == 0 ]]; then
      while IFS=$'\t' read -r name host kind; do
        if [[ "$name" == __WARNING__ ]]; then
          log "WARNING: $host"
        elif [[ -n "$host" ]]; then
          check_host_path "Saved template $name" "$host" '' "$kind"
        fi
      done <<< "$template_listing"
    else
      log "WARNING: Docker template parsing failed: ${template_listing:0:500}"
    fi
  else
    log 'PHP CLI unavailable: saved template inspection skipped.'
  fi
fi

if [[ "$ACCEPT_CURRENT" == 1 ]]; then
  log 'Accepted current folder snapshots. Explicit forbidden paths and other checks remain enabled.'
fi

if [[ -f "$ALERT_STATE" ]]; then
  while IFS='|' read -r id epoch; do
    [[ "$id" =~ ^[a-f0-9]{64}$ && "$epoch" =~ ^[0-9]+$ ]] && LAST_NOTIFIED["$id"]="$epoch"
  done < "$ALERT_STATE"
fi
now=$(date +%s)
reminder_seconds=$((REMINDER_HOURS * 3600))
notification_count=0
notification_priority=warning
notification_message=''
declare -A DUE=()
declare -a issue_ids=()
if (( ${#ISSUE_TEXT[@]} > 0 )); then
  mapfile -t issue_ids < <(printf '%s\n' "${!ISSUE_TEXT[@]}" | LC_ALL=C sort)
fi
for id in "${issue_ids[@]}"; do
  level="${ISSUE_LEVEL[$id]}"
  message="${ISSUE_TEXT[$id]}"
  log "[$level] $message"
  last="${LAST_NOTIFIED[$id]:-0}"
  if (( last == 0 || now - last >= reminder_seconds )); then
    DUE["$id"]=1
    notification_count=$((notification_count + 1))
    [[ "$level" == alert ]] && notification_priority=alert
    notification_message+="- $message"$'\n'
  fi
done

notification_sent=0
if (( notification_count > 0 )); then
  log "$notification_count finding(s) due for notification."
  if [[ "$SEND_NOTIFICATIONS" == 1 ]]; then
    notify_bin="$NOTIFY_SCRIPT"
    if [[ ! -x "$notify_bin" && -x /usr/local/emhttp/webGui/scripts/notify ]]; then
      notify_bin=/usr/local/emhttp/webGui/scripts/notify
    fi
    if [[ -x "$notify_bin" ]]; then
      if "$notify_bin" -e 'Unraid Path Guard' -s "Storage path warning ($notification_count)" \
        -d "$notification_count suspicious path(s). Check User Scripts log for full details." \
        -m "${notification_message:0:4500}" -i "$notification_priority"; then
        notification_sent=1
      else
        log 'WARNING: Unraid notification helper failed; retry on next scan.'
      fi
    else
      log "WARNING: Notification helper unavailable: $NOTIFY_SCRIPT"
    fi
  else
    log 'Notifications disabled; findings have not been marked as notified.'
  fi
fi

# Only successful notification sends advance their reminder clocks. Resolved
# issues leave the state file and will notify again if they reappear.
tmp_state=$(mktemp "$STATE_DIR/.alerts.XXXXXXXX") || { log_error 'Cannot create notification state temp file'; exit 1; }
for id in "${issue_ids[@]}"; do
  last="${LAST_NOTIFIED[$id]:-0}"
  [[ "$notification_sent" == 1 && -n "${DUE[$id]:-}" ]] && last="$now"
  printf '%s|%s\n' "$id" "$last" >> "$tmp_state" || { rm -f -- "$tmp_state"; log_error 'Cannot write notification state'; exit 1; }
done
if [[ -f "$ALERT_STATE" ]] && cmp -s -- "$ALERT_STATE" "$tmp_state"; then
  rm -f -- "$tmp_state"
else
  mv -f -- "$tmp_state" "$ALERT_STATE" || { rm -f -- "$tmp_state"; log_error "Cannot commit notification state: $ALERT_STATE"; exit 1; }
fi
log "Scan finished: ${#ISSUE_TEXT[@]} active concern(s)."
