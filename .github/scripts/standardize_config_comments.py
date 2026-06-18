#!/usr/bin/env python3
"""Standardize EDIT FOR YOUR SETUP inline comments across root *.sh scripts."""
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
NOTIFY_STD = "# Unraid Dynamix notify script (empty = disabled)"

REPLACEMENTS: list[tuple[str, str, str]] = [
    # (filename, old, new) — empty filename = all scripts
    ("", "# Unraid dynamix notify script\n", f"{NOTIFY_STD}\n"),
    ("", "# Unraid dynamix notify (default path; empty = disabled)\n", f"{NOTIFY_STD}\n"),
    ("", "# Optional: Unraid dynamix notify after run (empty = no notification)\n", f"{NOTIFY_STD}\n"),
    ("", "# Unraid notify script (dynamix plugin)\n", "# Unraid Dynamix notify script (used when ENABLE_NOTIFICATIONS=1)\n"),
    ("queue-sync-nzbget.sh", "# --- Behaviour ---", "# --- Behavior ---"),
    ("queue-sync-nzbget.sh", 'DRY_RUN="1"                # 1 = log only, no removals or searches (default)',
     'DRY_RUN="1"                # 1 = preview only, no removals or searches (default)'),
    ("queue-sync-nzbget.sh", 'TRIGGER_SEARCH="1"         # 0 = remove+blocklist only; 1 = remove, blocklist, and force search',
     'TRIGGER_SEARCH="1"         # 1 = trigger Radarr/Sonarr search after removal; 0 = remove only'),
    ("queue-sync-nzbget.sh", 'BLOCKLIST_ENABLED="1"      # 1 = blocklist release when removing from *arr queue; 0 = remove only',
     'BLOCKLIST_ENABLED="1"      # 1 = blocklist release when removing from Radarr/Sonarr queue; 0 = remove only'),
    ("queue-sync-nzbget.sh", 'SAFE_EMPTY_QUEUE="0"       # 1 = skip *arr removals when NZBGet queue is empty',
     'SAFE_EMPTY_QUEUE="0"       # 1 = skip Radarr/Sonarr removals when NZBGet queue is empty'),
    ("queue-sync-nzbget.sh", 'LOG_FILE=""               # If set, append logs here (e.g. /boot/config/queue-sync.log)',
     'LOG_FILE=""                # Append logs here (e.g. /boot/config/queue-sync.log; empty = stdout only)'),
    ("queue-sync-nzbget.sh", 'CURL_TIMEOUT="30"\nSEARCH_IDS_CHUNK_SIZE="50"  # Max IDs per MoviesSearch/EpisodeSearch request\nQUEUE_PAGE_SIZE="500"      # *arr queue page size (pagination handled)',
     'CURL_TIMEOUT="30"          # HTTP timeout in seconds for API calls\nSEARCH_IDS_CHUNK_SIZE="50"  # Max movie/episode IDs per search batch\nQUEUE_PAGE_SIZE="500"      # Radarr/Sonarr queue page size (raise if queue exceeds 500)'),
    ("apply-unraid-perms.sh", "# Behaviour\nDRY_RUN=\"1\"", "# Behavior\nDRY_RUN=\"1\"             # 1 = preview only, 0 = apply chmod changes"),
    ("check-smart-status.sh", "# Disks to check - leave empty to auto-detect via smartctl --scan",
     "# Disks to check (e.g. /dev/sda); leave empty to auto-detect all disks"),
    ("check-plex-status.sh", "# 0 = always restart when UI is unreachable (default); 1 = skip if restart policy is \"no\"",
     "# 0 = restart when UI is unreachable (default); 1 = skip unless policy is always or unless-stopped"),
    ("check-plex-status.sh", "# Timeout in seconds for web UI check\nCONNECT_TIMEOUT=\"15\"\nMAX_TIME=\"30\"",
     "# Curl timeouts in seconds\nCONNECT_TIMEOUT=\"15\"  # Connect timeout\nMAX_TIME=\"30\"           # Total timeout for web UI check"),
    ("clean-download-junk.sh", "# 1 = dry-run (no deletions), 0 = production",
     "# 1 = preview only (no deletions), 0 = delete files"),
    ("update-radarr-profiles.sh", "# 1 = dry run (no API changes), 0 = live",
     "# 1 = preview only (no API changes), 0 = apply updates"),
    ("update-radarr-profiles.sh", 'CURRENT_YEAR_PROFILE_ID="9"   # Profile for current year movies\nOLDER_MOVIES_PROFILE_ID="2"   # Profile for previous year and older movies',
     'CURRENT_YEAR_PROFILE_ID="9"   # Radarr → Settings → Profiles (ID column)\nOLDER_MOVIES_PROFILE_ID="2"   # Profile for older movies (Settings → Profiles)'),
    ("update-sonarr-profiles.sh", "# Enable/disable processing of each category (true/false)",
     "# Enable/disable processing of each category (1 or 0)"),
    ("update-sonarr-profiles.sh", "# 1 = dry run (no API changes), 0 = live",
     "# 1 = preview only (no API changes), 0 = apply updates"),
    ("user-scripts-updater.sh", "# 1 = dry run (no changes), 0 = apply",
     "# 1 = preview only (no changes), 0 = apply updates"),
    ("parity-check-monitor.sh", "# Path to Unraid var.ini",
     "# Unraid parity-check state (Settings → Scheduler → Parity Check)"),
    ("record-disk-assignments.sh", "# Unraid disks.ini path",
     "# Unraid disk assignments (Main → Array Devices)"),
    ("record-disk-assignments.sh", "# Output file path",
     "# Text report path (JSON written alongside when JSON_OUTPUT=1)"),
    ("disk-error-alert.sh", "# Grep -E patterns for md/storage errors (each is searched; union is de-duped)",
     "# Syslog text patterns for array/disk errors (one match per line is enough)"),
    ("remove-os-metadata.sh", "# Maximum depth (0 = unlimited). Use a number to limit depth.",
     "# Maximum find depth (9999 = effectively unlimited; lower to limit scan depth)"),
    ("btrfs-scrub.sh", "# Where to save scrub log output (default: /boot/logs/scrub.log if empty)",
     "# Scrub log file (empty at runtime falls back to /boot/logs/scrub.log)"),
    ("clear-plex-codecs.sh", "# 1 = only restart if container restart policy is always or unless-stopped",
     "# 0 = restart whenever RESTART_PLEX_CONTAINER=1; 1 = only if policy is always or unless-stopped"),
    ("docker-image-usage-alert.sh", "# State file for threshold escalation tracking",
     "# Alert escalation state (empty = docker-usage.state beside this script)"),
    ("out-of-memory-errors.sh", "# Persistent state file for tracking OOM count across runs",
     "# OOM count state (empty = oom-errors.state beside this script)"),
    ("flash-backup.sh", "# 1 = exclude files matching previous backup patterns from the archive",
     "# 1 = omit older flash-backup-*.tar.* files from new archive"),
    ("server-info-push.sh", "# Unraid dynamix notify when PUSH_NOTIFICATIONS=1 (empty = stdout only)",
     "# Unraid Dynamix notify script (used when PUSH_NOTIFICATIONS=1)"),
    ("server-info-push.sh", "# Mounts to report free space\nARRAY_MOUNT=\"/mnt/user\"\nCACHE_MOUNT=\"/mnt/downloads\"\nAPPDATA_MOUNT=\"/mnt/appdata\"",
     "# Mount points for free-space report\nARRAY_MOUNT=\"/mnt/user\"      # Main array share\nCACHE_MOUNT=\"/mnt/downloads\" # Cache/downloads pool\nAPPDATA_MOUNT=\"/mnt/appdata\"  # Appdata share"),
    ("delete-dangling-images.sh", "###############################################################################\n# EDIT FOR YOUR SETUP\n###############################################################################\n\nlog() {",
     "###############################################################################\n# EDIT FOR YOUR SETUP\n###############################################################################\n\n# No user configuration — prunes dangling Docker images.\n\nlog() {"),
]

LANG_GUARD_RADARR_OLD = '''# Radarr
RADARR_URL=""           # e.g. http://192.168.1.10:7878 (no trailing slash)
RADARR_API_KEY=""       # Settings → General → API Key

# 1 = dry run (recommended to start), 0 = live run
DRY_RUN="1"

# 1 = extra logging, 0 = normal
DEBUG="0"

# 1 = use ffprobe when Radarr metadata is missing
USE_FFPROBE_FALLBACK="0"

# Persistent files (empty = default beside script)
LOG_FILE=""
STATE_FILE=""
LOCK_FILE="/tmp/radarr-language-guard.lock"

# Throttles / safety limits
RATE_LIMIT_DELAY="1"
MAX_ACTIONS_PER_RUN="25"
SEARCH_COOLDOWN_DAYS="7"

# Optional targeting for tests / small batches
MOVIE_ID=""
MOVIE_FILTER=""

# Optional maintenance toggles
CLEAR_BLACKLIST="0"
BLACKLIST_DUMP="0"
STATS_DUMP="0"

# 1 = faster discovery pass (recommended), 0 = slower shell/jq path
FAST_DISCOVERY="1"'''

LANG_GUARD_RADARR_NEW = '''# --- Radarr ---
RADARR_URL=""           # e.g. http://192.168.1.10:7878 (no trailing slash)
RADARR_API_KEY=""       # Settings → General → API Key

DRY_RUN="1"             # 1 = preview only (recommended first), 0 = apply changes
DEBUG="0"               # 1 = extra logging, 0 = normal
USE_FFPROBE_FALLBACK="0"  # 1 = probe media with ffprobe when Radarr language metadata is missing

# Persistent files (empty = default beside this script)
LOG_FILE=""
STATE_FILE=""
LOCK_FILE="/tmp/radarr-language-guard.lock"

RATE_LIMIT_DELAY="1"    # Seconds between API calls
MAX_ACTIONS_PER_RUN="25"  # Max delete/search actions per run
SEARCH_COOLDOWN_DAYS="7"  # Min days before re-searching the same title

MOVIE_ID=""             # Limit to one Radarr movie ID (empty = full library)
MOVIE_FILTER=""         # Substring match on movie title (empty = all)

# Script state maintenance (not Radarr's release blocklist API)
CLEAR_BLACKLIST="0"     # 1 = clear script blacklist state and exit
BLACKLIST_DUMP="0"      # 1 = print script blacklist JSON and exit
STATS_DUMP="0"          # 1 = print script stats JSON and exit

FAST_DISCOVERY="1"      # 1 = faster Python discovery (recommended), 0 = Bash/jq discovery'''

LANG_GUARD_SONARR_OLD = '''# Sonarr
SONARR_URL=""           # e.g. http://192.168.1.10:8989 (no trailing slash)
SONARR_API_KEY=""       # Settings → General → API Key

# 1 = dry run (recommended to start), 0 = live run
DRY_RUN="1"

# 1 = extra logging, 0 = normal
DEBUG="0"

# 1 = use ffprobe when Sonarr metadata is missing
USE_FFPROBE_FALLBACK="0"

# Persistent files (empty = default beside script)
LOG_FILE=""
STATE_FILE=""
LOCK_FILE="/tmp/sonarr-language-guard.lock"

# Throttles / safety limits
RATE_LIMIT_DELAY="1"
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
FAST_DISCOVERY="1"'''

LANG_GUARD_SONARR_NEW = '''# --- Sonarr ---
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

FAST_DISCOVERY="1"      # 1 = faster Python discovery (recommended), 0 = Bash/jq discovery'''


def main() -> None:
    changed: list[str] = []
    for path in sorted(REPO.glob("*.sh")):
        text = path.read_text()
        orig = text
        name = path.name

        if name == "language-guard-radarr.sh":
            text = text.replace(LANG_GUARD_RADARR_OLD, LANG_GUARD_RADARR_NEW)
        elif name == "language-guard-sonarr.sh":
            text = text.replace(LANG_GUARD_SONARR_OLD, LANG_GUARD_SONARR_NEW)

        for file_filter, old, new in REPLACEMENTS:
            if file_filter and file_filter != name:
                continue
            if old in text:
                text = text.replace(old, new)

        # Trailing whitespace on blank line after EDIT block opener (clear-* scripts)
        if name.startswith("clear-") and name.endswith("-download-folder.sh"):
            text = text.replace(
                "# EDIT FOR YOUR SETUP\n###############################################################################\n \n",
                "# EDIT FOR YOUR SETUP\n###############################################################################\n\n",
            )

        if text != orig:
            path.write_text(text)
            changed.append(name)

    print(f"Updated {len(changed)} script(s):")
    for n in changed:
        print(f"  {n}")


if __name__ == "__main__":
    main()
