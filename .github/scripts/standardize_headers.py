#!/usr/bin/env python3
"""Standardize script header comments across repo root *.sh files."""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

NOTE = "# Note: Progress and errors print to stdout; Unraid User Scripts shows that in the run window. Optional LOG_FILE also appends a copy to disk."
FOOTER = """\
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0"""

CFG = "# Configuration (edit script variables below):"


def hdr(name: str, tagline: str, desc: list[str], usage: list[str], config: list[str], extra: list[str] | None = None) -> str:
    lines = [
        "#!/bin/bash",
        "#",
        f"# {name}",
        f"# {tagline}",
        "#",
        "# Description:",
        *[f"#   {line}" for line in desc],
        "#",
        "# Usage:",
        *[f"#   {line}" for line in usage],
        "#",
        CFG,
        *[f"#   - {line}" for line in config],
    ]
    if extra:
        lines.append("#")
        lines.extend(extra)
    lines.extend(["#", NOTE, "#", FOOTER, ""])
    return "\n".join(lines)


HEADERS: dict[str, str] = {
    "apply-unraid-perms.sh": hdr(
        "apply-unraid-perms.sh",
        "Apply Unraid-style permissions (nobody:users, Docker-safe) to configured paths.",
        [
            "Recursively chmod/chown paths for Unraid shares and Docker.",
            "Can take a long time on large arrays — check PERM_PATHS before running.",
        ],
        ["./apply-unraid-perms.sh", "Edit variables in EDIT FOR YOUR SETUP below.", "DRY_RUN: 1 = preview only, 0 = apply changes"],
        [
            "PERM_PATHS: directories to process",
            "OWNER_GROUP: chown target (default nobody:users)",
            "CHMOD_FLAGS: chmod flags (Docker-safe defaults)",
            "EXCLUDE_PATHS: globs to skip inside PERM_PATHS",
            "PARALLEL_JOBS: parallel xargs jobs (0 = sequential)",
            "DRY_RUN: 1 = preview only, 0 = apply changes",
        ],
        ["# Requires: root (run with sudo)"],
    ),
    "btrfs-scrub.sh": hdr(
        "btrfs-scrub.sh",
        "Run a Btrfs scrub and optionally notify via Unraid dynamix.",
        ["Scrubs SCRUB_DEVICE, logs output, and can notify on start, success, or failure."],
        ["./btrfs-scrub.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "SCRUB_DEVICE: mount or device to scrub",
            "LOG_FILE: scrub log path",
            "ENABLE_NOTIFICATIONS: 1 = Unraid notify, 0 = log only",
            "NOTIFY_SCRIPT: dynamix notify path",
            "RESUME_EXISTING: 1 = continue an in-progress scrub",
        ],
    ),
    "check-plex-status.sh": hdr(
        "check-plex-status.sh",
        "Check Plex container and web UI; restart if the UI is down.",
        ["Restarts the Plex Docker container when it runs but the web UI does not respond."],
        ["./check-plex-status.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "PLEX_CONTAINER_NAME: Docker container name",
            "PLEX_WEB_UI: URL for health check",
            "NOTIFY_SCRIPT: dynamix notify path (empty = no notify)",
            "LOG_FILE: optional log file (empty = stdout only)",
            "RESTART_ONLY_IF_AUTOSTART: 1 = skip restart if policy is no",
            "NOTIFY_ON_RECOVERY: 1 = notify when Plex recovers",
            "MAX_RESTARTS_PER_DAY: daily restart cap (0 = unlimited)",
            "CONNECT_TIMEOUT / MAX_TIME: curl timeouts for UI check",
        ],
    ),
    "check-smart-status.sh": hdr(
        "check-smart-status.sh",
        "Alert when any disk fails SMART health checks.",
        ["Schedule daily or weekly. Sends Unraid notification if a disk reports failed SMART."],
        ["./check-smart-status.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "DISKS: disk list (empty = auto-detect)",
            "NOTIFY_SCRIPT: dynamix notify path",
            "LOG_FILE: optional log file (empty = stdout only)",
        ],
        ["# Requires: root (run with sudo)"],
    ),
    "clean-docker-log-size.sh": hdr(
        "clean-docker-log-size.sh",
        "Truncate Docker container logs to free space in docker.img.",
        ["Shows before/after sizes. Safe for running containers."],
        ["./clean-docker-log-size.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        ["DOCKER_CONTAINERS_PATH: path to container log directory", "LOG_FILE: optional log file"],
    ),
    "clean-download-junk.sh": hdr(
        "clean-download-junk.sh",
        "Remove download junk files and empty folders (NZB, torrent, or both).",
        [
            "Consolidates clean-nzb-junk.sh and clean-torrent-junk.sh.",
            "Use PROFILE for preset paths and patterns, or custom with your own lists.",
        ],
        [
            "./clean-download-junk.sh",
            "Edit variables in EDIT FOR YOUR SETUP below.",
            "PROFILE: nzb, torrent, all, or custom",
            "DRY_RUN: 1 = preview only, 0 = delete files",
        ],
        [
            "PROFILE: nzb | torrent | all | custom",
            "FOLDERS / JUNK_EXTENSIONS: override profile defaults",
            "EXTRA_FOLDERS / EXTRA_JUNK_EXTENSIONS: append to profile",
            "MIN_AGE_MINUTES, EXCLUDE_PATTERNS, DELETE_SAMPLES, DELETE_EMPTY_DIRS",
            "DRY_RUN: 1 = preview only, 0 = delete files",
        ],
    ),
    "clean-nzb-junk.sh": hdr(
        "clean-nzb-junk.sh",
        "Remove NZB download junk files and empty folders.",
        ["Deletes common leftover files (nfo, par2, samples, archives) under FOLDERS."],
        ["./clean-nzb-junk.sh", "Edit variables in EDIT FOR YOUR SETUP below.", "DRY_RUN: 1 = preview only, 0 = delete files"],
        [
            "FOLDERS: directories to clean",
            "JUNK_EXTENSIONS: filename patterns to remove",
            "MIN_AGE_MINUTES: skip files newer than N minutes (0 = all)",
            "EXCLUDE_PATTERNS: globs to keep",
            "DRY_RUN: 1 = preview only, 0 = delete files",
        ],
    ),
    "clean-torrent-junk.sh": hdr(
        "clean-torrent-junk.sh",
        "Remove torrent download junk files and empty folders.",
        ["Same behaviour as clean-nzb-junk.sh for torrent download paths."],
        ["./clean-torrent-junk.sh", "Edit variables in EDIT FOR YOUR SETUP below.", "DRY_RUN: 1 = preview only, 0 = delete files"],
        [
            "FOLDERS: directories to clean",
            "JUNK_EXTENSIONS: filename patterns to remove",
            "MIN_AGE_MINUTES: skip files newer than N minutes (0 = all)",
            "EXCLUDE_PATTERNS: globs to keep",
            "DRY_RUN: 1 = preview only, 0 = delete files",
        ],
    ),
    "clear-movies-download-folder.sh": hdr(
        "clear-movies-download-folder.sh",
        "Empty the movies download folder (with optional age filter).",
        ["Deletes files under DIR_PATH. Use DRY_RUN first on production systems."],
        ["./clear-movies-download-folder.sh", "Edit variables in EDIT FOR YOUR SETUP below.", "DRY_RUN: 1 = preview only, 0 = delete files"],
        [
            "DIR_PATH: folder to clear",
            "MIN_AGE_MINUTES: skip files newer than N minutes (0 = all)",
            "DRY_RUN: 1 = preview only, 0 = delete files",
            "NOTIFY_SCRIPT: optional completion notify",
            "LOG_FILE: optional log file",
        ],
    ),
    "clear-torrent-download-folder.sh": hdr(
        "clear-torrent-download-folder.sh",
        "Empty the torrent download folder (with optional age filter).",
        ["Deletes files under DIR_PATH. Use DRY_RUN first on production systems."],
        ["./clear-torrent-download-folder.sh", "Edit variables in EDIT FOR YOUR SETUP below.", "DRY_RUN: 1 = preview only, 0 = delete files"],
        [
            "DIR_PATH: folder to clear",
            "MIN_AGE_MINUTES: skip files newer than N minutes (0 = all)",
            "DRY_RUN: 1 = preview only, 0 = delete files",
            "NOTIFY_SCRIPT: optional completion notify",
            "LOG_FILE: optional log file",
        ],
    ),
    "clear-tv-shows-download-folder.sh": hdr(
        "clear-tv-shows-download-folder.sh",
        "Empty the TV shows download folder (with optional age filter).",
        ["Deletes files under DIR_PATH. Use DRY_RUN first on production systems."],
        ["./clear-tv-shows-download-folder.sh", "Edit variables in EDIT FOR YOUR SETUP below.", "DRY_RUN: 1 = preview only, 0 = delete files"],
        [
            "DIR_PATH: folder to clear",
            "MIN_AGE_MINUTES: skip files newer than N minutes (0 = all)",
            "DRY_RUN: 1 = preview only, 0 = delete files",
            "NOTIFY_SCRIPT: optional completion notify",
            "LOG_FILE: optional log file",
        ],
    ),
    "clear-plex-codecs.sh": hdr(
        "clear-plex-codecs.sh",
        "Delete Plex codec cache (Plex re-downloads as needed).",
        ["Frees space under PLEX_CODECS_PATH. Plex may briefly re-transcode after clearing."],
        ["./clear-plex-codecs.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        ["PLEX_PATH: Plex appdata root (used when PLEX_CODECS_PATH is empty)", "PLEX_CODECS_PATH: codec cache directory (empty = under PLEX_PATH)"],
    ),
    "delete-dangling-images.sh": hdr(
        "delete-dangling-images.sh",
        "Remove untagged (dangling) Docker images to free docker.img space.",
        ["Only removes dangling images — not images in use by containers."],
        ["./delete-dangling-images.sh"],
        ["No user settings — runs docker rmi on dangling images"],
    ),
    "disk-error-alert.sh": hdr(
        "disk-error-alert.sh",
        "Alert on new md/storage errors in syslog.",
        ["Counts unique error lines and notifies only when the count increases."],
        ["./disk-error-alert.sh", "Schedule hourly or daily.", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "SYSLOG_PATH: syslog file to scan",
            "NOTIFY_SCRIPT: dynamix notify path",
            "ERROR_PATTERNS / EXCLUDE_PATTERNS: match filters",
            "ENABLE_PER_DISK_TRACKING: 1 = track per-disk IDs",
            "ENABLE_SMART_CORRELATION: 1 = cross-check SMART status",
            "SMARTCTL_PATH: smartctl binary path",
            "LOG_FILE / STATE_FILE: optional logging and state",
        ],
    ),
    "docker-image-usage-alert.sh": hdr(
        "docker-image-usage-alert.sh",
        "Alert when docker.img usage crosses warning or critical thresholds.",
        ["Notifies once per threshold crossing; resets when usage drops."],
        ["./docker-image-usage-alert.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "DOCKER_PATH: docker.img mount path",
            "WARNING_THRESHOLD_PCT / CRITICAL_THRESHOLD_PCT: alert levels",
            "SHOW_LARGEST_CONTAINERS / LARGEST_COUNT: optional container breakdown",
            "NOTIFY_SCRIPT: dynamix notify path",
            "LOG_FILE / STATE_FILE: optional logging and state",
        ],
    ),
    "flash-backup.sh": hdr(
        "flash-backup.sh",
        "Backup the Unraid boot flash drive to compressed archives on the array.",
        ["Rotates old backups and verifies archive integrity."],
        ["./flash-backup.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "BACKUP_DEST: backup directory on array",
            "KEEP_COUNT: number of backups to retain",
            "COMPRESSION: archive format (gz, xz, etc.)",
            "VERIFY_BACKUP: 1 = test archive after creation",
            "EXCLUDE_LOGS / EXCLUDE_PREVIOUS_BACKUPS: tarball exclusions",
            "MAX_BACKUP_SIZE_MB: abort if backup exceeds size",
            "NOTIFY_SCRIPT: dynamix notify path",
            "LOG_FILE: optional log file",
        ],
    ),
    "language-guard-radarr.sh": hdr(
        "language-guard-radarr.sh",
        "Audit Radarr movie audio languages; fix bad releases via blocklist, delete, and search.",
        [
            "English-original movies need English audio; other originals need English or original language.",
            "Defaults to dry run — set DRY_RUN=0 for live remediation.",
        ],
        [
            "./language-guard-radarr.sh",
            "Edit variables in EDIT FOR YOUR SETUP below.",
            "DRY_RUN: 1 = preview only (default), 0 = delete/blocklist/search",
        ],
        [
            "RADARR_URL / RADARR_API_KEY: Radarr connection",
            "DRY_RUN / DEBUG / USE_FFPROBE_FALLBACK",
            "LOG_FILE / STATE_FILE / LOCK_FILE: logging, state, and lock",
            "RATE_LIMIT_SECONDS / MAX_ACTIONS_PER_RUN / SEARCH_COOLDOWN_DAYS",
            "MOVIE_ID / MOVIE_FILTER: optional targeting",
            "CLEAR_BLACKLIST / BLACKLIST_DUMP / STATS_DUMP: maintenance modes",
            "FAST_DISCOVERY: 1 = faster Python discovery (recommended)",
        ],
        ["# Requires: curl, jq, python3 (ffprobe optional if USE_FFPROBE_FALLBACK=1)"],
    ),
    "language-guard-sonarr.sh": hdr(
        "language-guard-sonarr.sh",
        "Audit Sonarr episode audio languages; fix bad releases via blocklist, delete, and search.",
        [
            "Same language rules as language-guard-radarr.sh for TV episodes.",
            "Defaults to dry run — set DRY_RUN=0 for live remediation.",
        ],
        [
            "./language-guard-sonarr.sh",
            "Edit variables in EDIT FOR YOUR SETUP below.",
            "DRY_RUN: 1 = preview only (default), 0 = delete/blocklist/search",
        ],
        [
            "SONARR_URL / SONARR_API_KEY: Sonarr connection",
            "DRY_RUN / DEBUG / USE_FFPROBE_FALLBACK",
            "DELETE_ONLY_IF_REPLACEABLE: 1 = skip unmonitored or unreplaceable content",
            "LOG_FILE / STATE_FILE / LOCK_FILE",
            "RATE_LIMIT_SECONDS / MAX_ACTIONS_PER_RUN / SEARCH_COOLDOWN_DAYS",
            "SERIES_ID / SERIES_FILTER: optional targeting",
            "CLEAR_BLACKLIST / BLACKLIST_DUMP / STATS_DUMP",
            "FAST_DISCOVERY: 1 = faster Python discovery (recommended)",
        ],
        ["# Requires: curl, jq, python3 (ffprobe optional if USE_FFPROBE_FALLBACK=1)"],
    ),
    "out-of-memory-errors.sh": hdr(
        "out-of-memory-errors.sh",
        "Alert when new Out-of-Memory (OOM) events appear in syslog.",
        ["Tracks state so repeat alerts only fire for new OOM kills."],
        ["./out-of-memory-errors.sh", "Schedule hourly.", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "SYSLOG_PATH: syslog file to scan",
            "NOTIFY_SCRIPT: dynamix notify path",
            "SHOW_KILLED_PROCESSES: 1 = include killed process names",
            "ENABLE_STATE_TRACKING: 1 = persist last-seen count",
            "LOG_FILE / STATE_FILE: optional logging and state",
        ],
    ),
    "parity-check-monitor.sh": hdr(
        "parity-check-monitor.sh",
        "Monitor parity check progress and notify on milestones and completion.",
        ["Run on a schedule while a parity check is active. Exits quietly when idle."],
        ["./parity-check-monitor.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "VAR_INI: Unraid emhttp var.ini path",
            "NOTIFY_ON_START / NOTIFY_ON_PROGRESS / NOTIFY_ON_COMPLETION / NOTIFY_ON_ERRORS",
            "PROGRESS_MILESTONE_PCT: notify every N percent",
            "NOTIFY_SCRIPT: dynamix notify path",
            "LOG_FILE / STATE_FILE: optional logging and state",
        ],
    ),
    "queue-sync-nzbget.sh": hdr(
        "queue-sync-nzbget.sh",
        "Sync Sonarr/Radarr queues with NZBGet; remove stale items and trigger search.",
        [
            "Removes *arr queue entries when the download left NZBGet, optionally blocklists, and searches again.",
        ],
        [
            "./queue-sync-nzbget.sh",
            "Edit variables in EDIT FOR YOUR SETUP below.",
            "DRY_RUN: 1 = preview only, 0 = apply changes",
        ],
        [
            "RADARR_URL / RADARR_API_KEY / SKIP_RADARR",
            "SONARR_URL / SONARR_API_KEY / SKIP_SONARR",
            "NZBGET_URL / NZBGET_USER / NZBGET_PASS",
            "DRY_RUN / TRIGGER_SEARCH / BLOCKLIST_ENABLED / CLEAR_NZBGET_FAILED",
            "SAFE_EMPTY_QUEUE / LOCK_FILE / MAX_REMOVALS_PER_RUN",
            "RATE_LIMIT_DELAY / RETRY_COUNT / LOG_FILE / CURL_TIMEOUT",
            "SEARCH_IDS_CHUNK_SIZE / QUEUE_PAGE_SIZE / CLEAR_NZBGET_AGE_DAYS",
        ],
        ["# Requires: curl, jq (flock if LOCK_FILE is set)"],
    ),
    "record-disk-assignments.sh": hdr(
        "record-disk-assignments.sh",
        "Write current Unraid disk assignments to a text (and optional JSON) file.",
        ["Useful before hardware changes or array rebuilds."],
        ["./record-disk-assignments.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        ["DISKS_INI: path to disks.ini", "OUTPUT_FILE: text output path", "JSON_OUTPUT: 1 = also write .json"],
    ),
    "remove-os-metadata.sh": hdr(
        "remove-os-metadata.sh",
        "Remove macOS and Windows metadata files from media paths.",
        ["Deletes .DS_Store, Thumbs.db, resource forks, etc. Defaults to dry run."],
        [
            "./remove-os-metadata.sh",
            "Edit variables in EDIT FOR YOUR SETUP below.",
            "DRY_RUN: 1 = preview only (default), 0 = delete files",
        ],
        [
            "SEARCH_PATHS: directories to scan",
            "MAX_DEPTH: find depth limit",
            "DELETE_MACOS_METADATA / DELETE_WINDOWS_METADATA / INCLUDE_RESOURCE_FORKS",
            "DRY_RUN: 1 = preview only, 0 = delete files",
            "LOG_FILE: optional log file",
        ],
    ),
    "server-info-push.sh": hdr(
        "server-info-push.sh",
        "Send a server status summary via Unraid dynamix notify.",
        ["Reports storage, temps, RAM, uptime, VMs, containers, and optional UPS."],
        ["./server-info-push.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "PUSH_NOTIFICATIONS: 1 = send notify, 0 = print only",
            "NOTIFY_SCRIPT: dynamix notify path",
            "ARRAY_MOUNT / CACHE_MOUNT / APPDATA_MOUNT",
            "INCLUDE_UPS / NUT_UPS_NAME",
            "SHOW_STORAGE / SHOW_TEMPS / SHOW_MEMORY / SHOW_UPTIME_LOAD / SHOW_VMS / SHOW_CONTAINERS / SHOW_UPS",
        ],
    ),
    "update-radarr-profiles.sh": hdr(
        "update-radarr-profiles.sh",
        "Assign Radarr quality profiles by movie year window.",
        ["Recent years → premium profile; older years → default profile."],
        [
            "./update-radarr-profiles.sh",
            "Edit variables in EDIT FOR YOUR SETUP below.",
            "DRY_RUN: 1 = preview only, 0 = update Radarr",
        ],
        [
            "RADARR_URL / RADARR_API_KEY",
            "CURRENT_YEAR_PROFILE_ID / OLDER_MOVIES_PROFILE_ID",
            "PROCESS_CURRENT_YEAR / PROCESS_PREVIOUS_YEAR / PREMIUM_YEARS_BACK",
            "CUSTOM_CURRENT_YEAR / CUSTOM_PREVIOUS_YEAR",
            "DRY_RUN / MONITORED_ONLY / TRIGGER_SEARCH / MAX_UPDATES_PER_RUN",
            "CURL_TIMEOUT / RATE_LIMIT_DELAY / RETRY_COUNT / RADARR_VERIFY_SSL",
            "LOG_VERBOSE / LOG_FILE / NOTIFY_SCRIPT",
        ],
    ),
    "update-sonarr-profiles.sh": hdr(
        "update-sonarr-profiles.sh",
        "Assign Sonarr quality profiles by show status (airing, upcoming, ended, continuing).",
        ["Uses nextAiring and status to pick the target profile."],
        [
            "./update-sonarr-profiles.sh",
            "Edit variables in EDIT FOR YOUR SETUP below.",
            "DRY_RUN: 1 = preview only, 0 = update Sonarr",
        ],
        [
            "SONARR_URL / SONARR_API_KEY",
            "AIRING_PROFILE_ID / UPCOMING_PROFILE_ID / ENDED_PROFILE_ID / CONTINUING_NO_UPCOMING_PROFILE_ID",
            "PROCESS_AIRING / PROCESS_UPCOMING / PROCESS_ENDED / PROCESS_CONTINUING_NO_UPCOMING: \"true\" or \"false\"",
            "AIRING_DAYS / UPCOMING_DAYS",
            "DRY_RUN / MONITORED_ONLY / TRIGGER_SEARCH / MAX_UPDATES_PER_RUN",
            "CURL_TIMEOUT / RATE_LIMIT_DELAY / RETRY_COUNT / SONARR_VERIFY_SSL",
            "LOG_VERBOSE / LOG_FILE / NOTIFY_SCRIPT",
        ],
    ),
    "user-scripts-updater.sh": hdr(
        "user-scripts-updater.sh",
        "Update User Scripts plugin folders from GitHub while keeping your config edits.",
        [
            "Downloads this repo (or uses a local copy), updates installed script folders, and merges EDIT FOR YOUR SETUP blocks.",
        ],
        [
            "Run from User Scripts (foreground first, then schedule).",
            "Edit variables in EDIT FOR YOUR SETUP below.",
            "DRY_RUN: 1 = preview only (default), 0 = apply updates",
        ],
        [
            "SOURCE_MODE: zip or local",
            "ZIP_URL / REPO_DIR / DEST_DIR",
            "FETCH_UPDATES / CLEAR_CACHE / INSTALL_MISSING",
            "DRY_RUN / BACKUP_DIR / WORK_DIR",
            "RESET_CONFIG / CONFIG_CONFLICT_MODE / SHOW_CONFIG_DIFF",
            "INCLUDE_FOLDERS / EXCLUDE_FOLDERS",
            "DOWNLOAD_CONNECT_TIMEOUT / DOWNLOAD_MAX_TIME",
        ],
    ),
    "view-docker-log-size.sh": hdr(
        "view-docker-log-size.sh",
        "List Docker container log file sizes (largest first).",
        ["Helps find logs filling docker.img."],
        ["./view-docker-log-size.sh", "Edit variables in EDIT FOR YOUR SETUP below."],
        [
            "DOCKER_CONTAINERS_PATH: container logs directory",
            "HEAD_COUNT: number of lines to show",
            "PER_CONTAINER_BREAKDOWN: 1 = group by container name",
            "SHOW_TREND / TREND_FILE: optional size trend tracking",
        ],
    ),
}


def patch_file(path: Path, header: str) -> None:
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^set -u\b", text, re.MULTILINE)
    if not m:
        raise SystemExit(f"no set -u in {path.name}")
    new_text = header.rstrip() + "\n\n" + text[m.start() :].lstrip()
    path.write_text(new_text, encoding="utf-8")


def main() -> None:
    for name, header in sorted(HEADERS.items()):
        path = REPO / name
        if not path.is_file():
            raise SystemExit(f"missing {name}")
        patch_file(path, header)
        print(f"updated {name}")


if __name__ == "__main__":
    main()
