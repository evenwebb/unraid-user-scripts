# Unraid User Scripts

Bash scripts for Unraid, designed to be used with the **User Scripts** plugin.

**Repository:** [github.com/evenwebb/unraid-user-scripts](https://github.com/evenwebb/unraid-user-scripts) · **Author:** [evenwebb](https://github.com/evenwebb) · **License:** [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html)

> **💡 Tip:** Pre-configured User Scripts plugin folders are available in the `user-scripts-folders/` directory. Copy them directly to your Unraid flash drive for easy installation!

All scripts use a consistent format: header block, `set -u`, config variables at the top, `log()` helper, and `main "$@"`. Edit configuration at the top of each script and remove or replace any placeholder credentials/paths before use.

## Featured: User Scripts Updater (recommended)

Keeping scripts updated is annoying, especially if you’ve edited variables (URLs, API keys, paths, profile IDs, etc.) inside the script. **`user-scripts-updater.sh`** solves that by updating the User Scripts plugin folders from GitHub while **preserving your local config edits**.

- **What it does**
  - Downloads the latest scripts from GitHub (**no `git` required on Unraid**)
  - Updates `/boot/config/plugins/user.scripts/scripts/…` from the repo’s `user-scripts-folders/`
  - By default, it **only updates scripts you already have installed** (it will not install new script folders unless you enable it)
  - **Merges your “EDIT FOR YOUR SETUP” config block** so:
    - your existing variable values stay the same after updates
    - new upstream variables are added automatically using upstream defaults
    - renamed/removed variables are kept (and annotated) so you don’t lose settings
  - Saves backups of replaced scripts (configurable)

- **Why it’s useful even if you only use one script**
  - You can safely pull bug fixes and new features without re-doing your local edits.

- **Suggested schedule**
  - **Weekly** (e.g. Sunday night) is a good default for most users.
  - If you prefer faster updates, run it **daily**. It uses a cached ZIP and will skip downloading when nothing changed.

- **Safety tip**
  - Start with `DRY_RUN="1"` to verify what it would change, then switch to `DRY_RUN="0"` once you’re happy.
  - If you want it to install scripts you do not already have, set `INSTALL_MISSING="1"` for a run.

- **Unraid UI tip (foreground first)**
  - In the User Scripts plugin, use **Run Script** (foreground) the first time so you can read the output.
  - Most scripts support **dry run** mode. When `DRY_RUN="1"`, they will print what they would do and any useful summary data.
  - Once you are happy with the dry run output, switch to `DRY_RUN="0"` and then use **Run in Background** and/or schedule it.

## Scripts (root directory)

| Script | Description |
|:-------|:------------|
| **apply-unraid-perms.sh** | Applies Unraid-style "new permissions" (nobody:users, Docker-safe) to configured paths.<br>📝 **Config:** `PERM_PATHS` (e.g. `/mnt/user`, `/mnt/appdata`, `/mnt/downloads`), `OWNER_GROUP`, `CHMOD_FLAGS`<br>🔐 **Requires:** root (run with sudo)<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script |
| **btrfs-scrub.sh** | Runs a Btrfs scrub on a cache/device, logs output, and sends Unraid notifications on start/success/failure.<br>📝 **Config:** `SCRUB_DEVICE` (e.g. /mnt/cache, /mnt/downloads), `LOG_FILE`, `NOTIFY_SCRIPT`<br>📬 **Notifications:** Unraid dynamix (start/success/failure) |
| **check-plex-status.sh** | Checks if the Plex Docker container is running and if the web UI responds; restarts the container if the UI is unreachable.<br>📝 **Config:** `PLEX_CONTAINER_NAME`, `PLEX_WEB_UI`, optional Pushover keys, optional `LOG_FILE`, `RESTART_ONLY_IF_AUTOSTART`<br>📬 **Notifications:** Optional Pushover |
| **check-smart-status.sh** | Checks SMART health status of disks and sends an Unraid dynamix alert if any fail. Schedule (e.g. daily).<br>📝 **Config:** `DISKS` (empty = auto-detect), `NOTIFY_SCRIPT`, optional `LOG_FILE`<br>📋 **Logging:** stdout (Unraid GUI); optional `LOG_FILE` appends when set (path validated)<br>🔐 **Requires:** root (run with sudo)<br>📬 **Notifications:** Unraid dynamix |
| **clean-docker-log-size.sh** | Truncates Docker container log files to free space in docker.img. Shows before/after sizes.<br>📝 **Config:** `DOCKER_CONTAINERS_PATH`, optional `LOG_FILE` |
| **clean-nzb-junk.sh** | Removes NZB download junk (nfo, par2, samples, RAR splits, etc.) and empty directories.<br>📝 **Config:** `FOLDERS`, `JUNK_EXTENSIONS`<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script |
| **clean-torrent-junk.sh** | Removes torrent download junk (nfo, par2, samples, RAR splits, etc.) and empty directories.<br>📝 **Config:** `FOLDERS`, `JUNK_EXTENSIONS`<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script |
| **clear-movies-download-folder.sh** | Empties the movies download directory and prints a summary.<br>📝 **Config:** `DIR_PATH`, optional Pushover keys, optional `LOG_FILE`<br>📬 **Notifications:** Optional Pushover |
| **clear-plex-codecs.sh** | Deletes Plex Media Server codec cache (Plex re-downloads as needed).<br>📝 **Config:** `PLEX_CODECS_PATH` |
| **clear-torrent-download-folder.sh** | Empties the torrent download directory and prints a summary.<br>📝 **Config:** `DIR_PATH`, optional Pushover keys, optional `LOG_FILE`<br>📬 **Notifications:** Optional Pushover |
| **clear-tv-shows-download-folder.sh** | Empties the TV shows download directory and prints a summary.<br>📝 **Config:** `DIR_PATH`, optional Pushover keys, optional `LOG_FILE`<br>📬 **Notifications:** Optional Pushover |
| **delete-dangling-images.sh** | Removes Docker images with no tag (dangling) to free space in docker.img.<br>✅ **No configuration required** |
| **disk-error-alert.sh** | Checks syslog for md/storage errors and sends an Unraid dynamix alert if found. Schedule (e.g. hourly). Excludes common false positives (e.g. "no read error").<br>📝 **Config:** `SYSLOG_PATH`, `NOTIFY_SCRIPT`, `ERROR_PATTERNS`, `EXCLUDE_PATTERNS`, optional `LOG_FILE`<br>📋 **Logging:** stdout (Unraid GUI); optional `LOG_FILE` appends when set (path validated)<br>📬 **Notifications:** Unraid dynamix |
| **language-guard-radarr.sh** | Audits Radarr movie files for acceptable audio languages and remediates bad releases by blocklisting, deleting, and re-searching.<br>📝 **Config:** `RADARR_URL`, `RADARR_API_KEY`, `STATE_FILE`, `LOG_FILE`, `MAX_ACTIONS_PER_RUN`, `SEARCH_COOLDOWN_DAYS`, optional `MOVIE_ID`, `MOVIE_FILTER`<br>📋 **Logging:** stdout (Unraid GUI) plus persistent stats/state in `STATE_FILE`<br>🧪 **Dry-run:** Script defaults to `DRY_RUN=1`<br>⚙️ **Dependencies:** curl, jq (`ffprobe` optional) |
| **language-guard-sonarr.sh** | Audits Sonarr episode files for acceptable audio languages and remediates bad releases by blocklisting, deleting, and re-searching.<br>📝 **Config:** `SONARR_URL`, `SONARR_API_KEY`, `STATE_FILE`, `LOG_FILE`, `MAX_ACTIONS_PER_RUN`, `SEARCH_COOLDOWN_DAYS`, `DELETE_ONLY_IF_REPLACEABLE`, optional `SERIES_ID`, `SERIES_FILTER`<br>📋 **Logging:** stdout (Unraid GUI) plus persistent stats/state in `STATE_FILE`<br>🧪 **Dry-run:** Script defaults to `DRY_RUN=1`<br>⚙️ **Dependencies:** curl, jq (`ffprobe` optional) |
| **out-of-memory-errors.sh** | Checks syslog for "Out of memory" and sends an Unraid dynamix alert if found. Schedule (e.g. hourly).<br>📝 **Config:** `SYSLOG_PATH`, `NOTIFY_SCRIPT`, optional `LOG_FILE` |
| **queue-sync-nzbget.sh** | Syncs Sonarr/Radarr queues with NZBGet: removes \*arr queue entries when the download is gone from NZBGet, blocklists, and triggers search.<br>📝 **Config:** Radarr/Sonarr/NZBGet URLs and API keys/passwords; edit in script<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script<br>⚙️ **Dependencies:** curl, jq |
| **record-disk-assignments.sh** | Writes current Unraid disk assignments to `/boot/config/DISK_ASSIGNMENTS.txt`.<br>📝 **Config:** `DISKS_INI`, `OUTPUT_FILE` |
| **remove-os-metadata.sh** | Removes macOS metadata files (`.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`, etc.) and Windows metadata files (`Thumbs.db`, `desktop.ini`, etc.).<br>📝 **Config:** `SEARCH_PATHS`, `MAX_DEPTH`, `DELETE_MACOS_METADATA`, `DELETE_WINDOWS_METADATA`, `INCLUDE_RESOURCE_FORKS`, optional `LOG_FILE` |
| **server-info-push.sh** | Sends a styled status summary (storage, temps, RAM, uptime, UPS, VMs, containers) via Pushover or Pushbullet. Hides Docker section when Docker is not started.<br>📝 **Config:** `PUSH_NOTIFICATIONS`, Pushover/Pushbullet keys, mount paths, `INCLUDE_UPS`, `NUT_UPS_NAME`<br>📬 **Notifications:** Pushover or Pushbullet |
| **user-scripts-updater.sh** | Updates Unraid User Scripts plugin folders from a GitHub ZIP download (no git required) while preserving your edited config variables across updates.<br>📝 **Config:** `SOURCE_MODE`, `ZIP_URL`, `REPO_DIR`, `DEST_DIR`, `FETCH_UPDATES`, `DRY_RUN`, `BACKUP_DIR`, `WORK_DIR` |
| **update-radarr-profiles.sh** | Updates Radarr quality profiles by year window: premium years (current year back `PREMIUM_YEARS_BACK`) → one profile, older years → older movies profile.<br>📝 **Config:** Radarr URL/key, profile IDs, `PREMIUM_YEARS_BACK`, `CURL_TIMEOUT`, `RATE_LIMIT_DELAY`, `MAX_UPDATES_PER_RUN`, `LOG_VERBOSE`, `MONITORED_ONLY`, `TRIGGER_SEARCH`, `RETRY_COUNT`, optional Pushover, optional `LOG_FILE`<br>📋 **Logging:** stdout (Unraid GUI); optional `LOG_FILE` appends when set (path validated)<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script |
| **update-sonarr-profiles.sh** | Updates Sonarr quality profiles by show status: airing, upcoming, ended, continuing with no upcoming.<br>📝 **Config:** Sonarr URL/key, profile IDs per category, `AIRING_DAYS`, `UPCOMING_DAYS`, `PROCESS_*`, optional Pushover, optional `LOG_FILE`<br>📋 **Logging:** stdout (Unraid GUI); optional `LOG_FILE` appends when set (path validated)<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script |
| **view-docker-log-size.sh** | Lists Docker container log file sizes (largest first) to see if logging is filling docker.img.<br>📝 **Config:** `DOCKER_CONTAINERS_PATH`, `HEAD_COUNT` |

## Script format

All scripts in the repository root follow a consistent format:

- A standard header (name, description, usage, configuration, author, license)
- `set -u`
- Configuration variables at the top with “EDIT FOR YOUR SETUP” where needed
- No personal information (use placeholders for API keys, paths, passwords)
- A `log()` function and a `main` entry point

## Unraid compatibility and dependencies

These scripts target the latest public Unraid releases and are intended to run from the **User Scripts** plugin.

- **Python3**
  - `language-guard-*.sh` requires `python3`, which can be installed via the Python3 plugin on Unraid.

## Installation (Unraid User Scripts)

**Get the scripts:** Clone or download from [https://github.com/evenwebb/unraid-user-scripts](https://github.com/evenwebb/unraid-user-scripts).

### Method 1: Manual Creation (via Web UI)

1. Install the **User Scripts** plugin from Community Applications.
2. **Settings → User Scripts → Add New Script** (or edit existing).
3. Paste the contents of the desired script from the repo root (e.g. `clean-nzb-junk.sh`).
4. Edit the configuration section at the top (paths, API keys, etc.).
5. Save and schedule or run manually.

### Method 2: Copy Folder Structure (Recommended)

The User Scripts plugin stores scripts in `/boot/config/plugins/user.scripts/scripts/` on the flash drive. Each script requires a folder containing:
- `script` - The actual script file
- `description` - Description text (shown in the plugin UI)
- `name` - Display name (shown in the plugin UI)

**Pre-generated folders are available:** This repository includes a `user-scripts-folders/` directory with all scripts pre-configured for the User Scripts plugin. These folders are automatically generated by a GitHub Action whenever scripts are updated.

**To use this method:**
1. Download or clone this repository.
2. Copy the entire `user-scripts-folders/` directory contents to `/boot/config/plugins/user.scripts/scripts/` on your Unraid flash drive (or copy individual script folders as needed).
3. The scripts will automatically appear in the User Scripts plugin with their names and descriptions.
4. Edit the configuration section in each script's `script` file as needed.
5. Schedule or run manually from the plugin UI.

**Note:** The folders in `user-scripts-folders/` are auto-generated. To regenerate them manually, run `.github/scripts/generate_folders.py`.

## Clean NZB Junk - quick reference

- **Config:** `FOLDERS` (download dirs), `JUNK_EXTENSIONS` (optional).
- **Dry-run:** Set `DRY_RUN=1` in the script
- **Run:** `./clean-nzb-junk.sh`

## Author

[Steven (evenwebb)](https://github.com/evenwebb) · [unraid-user-scripts](https://github.com/evenwebb/unraid-user-scripts)

## License

GNU General Public License v3.0. See [LICENSE](LICENSE) or [https://www.gnu.org/licenses/gpl-3.0.html](https://www.gnu.org/licenses/gpl-3.0.html).

## Contributing

Open issues or pull requests as needed. Test changes before submitting.
