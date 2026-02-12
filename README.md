# Unraid User Scripts

Bash scripts for Unraid, designed to be used with the **User Scripts** plugin.

**Repository:** [github.com/evenwebb/unraid-user-scripts](https://github.com/evenwebb/unraid-user-scripts) · **Author:** [evenwebb](https://github.com/evenwebb) · **License:** [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html)

> **💡 Tip:** Pre-configured User Scripts plugin folders are available in the `user-scripts-folders/` directory. Copy them directly to your Unraid flash drive for easy installation!

All scripts use a consistent format: header block, `set -u`, config variables at the top, `log()` helper, and `main "$@"`. Edit configuration at the top of each script and remove or replace any placeholder credentials/paths before use.

## Scripts (root directory)

| Script | Description |
|:-------|:------------|
| **apply-unraid-perms.sh** | Applies Unraid-style "new permissions" (nobody:users, Docker-safe) to configured paths.<br>📝 **Config:** `PERM_PATHS` (e.g. `/mnt/user`, `/mnt/appdata`, `/mnt/downloads`), `OWNER_GROUP`, `CHMOD_FLAGS`<br>🔐 **Requires:** root (run with sudo)<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script |
| **btrfs-scrub.sh** | Runs a Btrfs scrub on a cache/device, logs output, and sends Unraid notifications on start/success/failure.<br>📝 **Config:** `SCRUB_DEVICE` (e.g. /mnt/cache, /mnt/downloads), `LOG_FILE`, `NOTIFY_SCRIPT`<br>📬 **Notifications:** Unraid dynamix (start/success/failure) |
| **check-plex-status.sh** | Checks if the Plex Docker container is running and if the web UI responds; restarts the container if the UI is unreachable.<br>📝 **Config:** `PLEX_CONTAINER_NAME`, `PLEX_WEB_UI`, optional Pushover keys, optional `LOG_FILE`, `RESTART_ONLY_IF_AUTOSTART`<br>📬 **Notifications:** Optional Pushover |
| **clean-docker-log-size.sh** | Truncates Docker container log files to free space in docker.img. Shows before/after sizes.<br>📝 **Config:** `DOCKER_CONTAINERS_PATH`, optional `LOG_FILE` |
| **clean-nzb-junk.sh** | Removes NZB download junk (nfo, par2, samples, RAR splits, etc.) and empty directories.<br>📝 **Config:** `FOLDERS`, `JUNK_EXTENSIONS`, optional `LOG_FILE`<br>🧪 **Dry-run:** Set `DEBUG=1` in script |
| **clear-movies-download-folder.sh** | Empties the movies download directory and prints a summary.<br>📝 **Config:** `DIR_PATH`, optional Pushover keys, optional `LOG_FILE`<br>📬 **Notifications:** Optional Pushover |
| **clear-plex-codecs.sh** | Deletes Plex Media Server codec cache (Plex re-downloads as needed).<br>📝 **Config:** `PLEX_CODECS_PATH` |
| **clear-torrent-download-folder.sh** | Empties the torrent download directory and prints a summary.<br>📝 **Config:** `DIR_PATH`, optional Pushover keys, optional `LOG_FILE`<br>📬 **Notifications:** Optional Pushover |
| **clear-tv-shows-download-folder.sh** | Empties the TV shows download directory and prints a summary.<br>📝 **Config:** `DIR_PATH`, optional Pushover keys, optional `LOG_FILE`<br>📬 **Notifications:** Optional Pushover |
| **delete-dangling-images.sh** | Removes Docker images with no tag (dangling) to free space in docker.img.<br>✅ **No configuration required** |
| **remove-os-metadata.sh** | Removes macOS metadata files (`.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`, etc.) and Windows metadata files (`Thumbs.db`, `desktop.ini`, etc.).<br>📝 **Config:** `SEARCH_PATHS`, `MAX_DEPTH`, `DELETE_MACOS_METADATA`, `DELETE_WINDOWS_METADATA`, `INCLUDE_RESOURCE_FORKS`, optional `LOG_FILE` |
| **out-of-memory-errors.sh** | Checks syslog for "Out of memory" and sends an Unraid dynamix alert if found. Schedule (e.g. hourly).<br>📝 **Config:** `SYSLOG_PATH`, `NOTIFY_SCRIPT`, optional `LOG_FILE` |
| **queue-sync-nzbget.sh** | Syncs Sonarr/Radarr queues with NZBGet: removes \*arr queue entries when the download is gone from NZBGet, blocklists, and triggers search.<br>📝 **Config:** Radarr/Sonarr/NZBGet URLs and API keys/passwords; edit in script<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script<br>⚙️ **Dependencies:** curl, jq |
| **record-disk-assignments.sh** | Writes current Unraid disk assignments to `/boot/config/DISK_ASSIGNMENTS.txt`.<br>📝 **Config:** `DISKS_INI`, `OUTPUT_FILE` |
| **server-info-push.sh** | Sends a styled status summary (storage, temps, RAM, uptime, UPS, VMs, containers) via Pushover or Pushbullet. Hides Docker section when Docker is not started.<br>📝 **Config:** `PUSH_NOTIFICATIONS`, Pushover/Pushbullet keys, mount paths, `INCLUDE_UPS`, `NUT_UPS_NAME`<br>📬 **Notifications:** Pushover or Pushbullet |
| **update-radarr-profiles.sh** | Updates Radarr quality profiles by year: current year → one profile, previous year → older movies profile.<br>📝 **Config:** Radarr URL/key, profile IDs, `CURL_TIMEOUT`, `RATE_LIMIT_DELAY`, `MAX_UPDATES_PER_RUN`, `LOG_VERBOSE`, `MONITORED_ONLY`, `TRIGGER_SEARCH`, `RETRY_COUNT`, optional Pushover, optional `LOG_FILE`<br>📋 **Logging:** stdout (Unraid GUI); optional `LOG_FILE` appends when set (path validated)<br>🧪 **Dry-run:** Set `DRY_RUN=1` in script |
| **view-docker-log-size.sh** | Lists Docker container log file sizes (largest first) to see if logging is filling docker.img.<br>📝 **Config:** `DOCKER_CONTAINERS_PATH`, `HEAD_COUNT` |

## Script format

All scripts in the repository root follow a consistent format:

- A standard header (name, description, usage, configuration, author, license)
- `set -u`
- Configuration variables at the top with “EDIT FOR YOUR SETUP” where needed
- No personal information (use placeholders for API keys, paths, passwords)
- A `log()` function and a `main` entry point

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
- `script` — The actual script file
- `description` — Description text (shown in the plugin UI)
- `name` — Display name (shown in the plugin UI)

**Pre-generated folders are available:** This repository includes a `user-scripts-folders/` directory with all scripts pre-configured for the User Scripts plugin. These folders are automatically generated by a GitHub Action whenever scripts are updated.

**To use this method:**
1. Download or clone this repository.
2. Copy the entire `user-scripts-folders/` directory contents to `/boot/config/plugins/user.scripts/scripts/` on your Unraid flash drive (or copy individual script folders as needed).
3. The scripts will automatically appear in the User Scripts plugin with their names and descriptions.
4. Edit the configuration section in each script's `script` file as needed.
5. Schedule or run manually from the plugin UI.

**Note:** The folders in `user-scripts-folders/` are auto-generated. To regenerate them manually, run `.github/scripts/generate_folders.py`.

## Clean NZB Junk – quick reference

- **Config:** `FOLDERS` (download dirs), `JUNK_EXTENSIONS` (optional).
- **Dry-run:** Set `DEBUG=1` in the script
- **Run:** `./clean-nzb-junk.sh`

## Author

[Steven (evenwebb)](https://github.com/evenwebb) · [unraid-user-scripts](https://github.com/evenwebb/unraid-user-scripts)

## License

GNU General Public License v3.0. See [LICENSE](LICENSE) or [https://www.gnu.org/licenses/gpl-3.0.html](https://www.gnu.org/licenses/gpl-3.0.html).

## Contributing

Open issues or pull requests as needed. Test changes before submitting.
