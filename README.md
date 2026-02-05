# Unraid User Scripts

Bash scripts for Unraid, designed to be used with the **User Scripts** plugin.

**Repository:** [github.com/evenwebb/unraid-user-scripts](https://github.com/evenwebb/unraid-user-scripts) · **Author:** [evenwebb](https://github.com/evenwebb) · **License:** [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html)

> **💡 Tip:** Pre-configured User Scripts plugin folders are available in the `user-scripts-folders/` directory. Copy them directly to your Unraid flash drive for easy installation!

All scripts use a consistent format: header block, `set -u`, config variables at the top, `log()` helper, and `main "$@"`. Edit configuration at the top of each script and remove or replace any placeholder credentials/paths before use.

## Scripts (root directory)

| Script | Description |
|:-------|:------------|
| **apply-unraid-perms.sh** | Applies Unraid-style "new permissions" (nobody:users, Docker-safe) to configured paths.<br>📝 **Config:** `PERM_PATHS` (e.g. `/mnt/user`, `/mnt/appdata`, `/mnt/downloads`) |
| **btrfs-scrub.sh** | Runs a Btrfs scrub on a cache/device, logs output, and sends Unraid notifications on start/success/failure.<br>📝 **Config:** `SCRUB_DEVICE` and optional `LOG_FILE` |
| **check-plex-status.sh** | Checks if the Plex Docker container is running and if the web UI responds; restarts the container if the UI is unreachable.<br>📝 **Config:** `PLEX_CONTAINER_NAME`, `PLEX_WEB_UI`, and optionally Pushover keys<br>📬 **Notifications:** Optional Pushover |
| **clean-docker-log-size.sh** | Truncates Docker container log files to free space in docker.img. Shows before/after sizes.<br>📝 **Config:** `DOCKER_CONTAINERS_PATH` if needed |
| **clean-nzb-junk.sh** | Removes NZB download junk (nfo, par2, samples, RAR splits, etc.) and empty directories.<br>📝 **Config:** `FOLDERS` and optionally `JUNK_EXTENSIONS`<br>🧪 **Dry-run:** `DEBUG=1` |
| **clear-movies-download-folder.sh** | Empties the movies download directory and prints a summary.<br>📝 **Config:** `DIR_PATH` and optionally Pushover keys<br>📬 **Notifications:** Optional Pushover |
| **clear-plex-codecs.sh** | Deletes Plex Media Server codec cache (Plex re-downloads as needed).<br>📝 **Config:** `PLEX_CODECS_PATH` for your appdata path |
| **clear-torrent-download-folder.sh** | Empties the torrent download directory and prints a summary.<br>📝 **Config:** `DIR_PATH` and optionally Pushover keys<br>📬 **Notifications:** Optional Pushover |
| **clear-tv-shows-download-folder.sh** | Empties the TV shows download directory and prints a summary.<br>📝 **Config:** `DIR_PATH` and optionally Pushover keys<br>📬 **Notifications:** Optional Pushover |
| **delete-dangling-images.sh** | Removes Docker images with no tag (dangling) to free space in docker.img.<br>✅ **No configuration required** |
| **remove-os-metadata.sh** | Removes macOS metadata files (`.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`, etc.) and Windows metadata files (`Thumbs.db`, `desktop.ini`, etc.).<br>📝 **Config:** `SEARCH_PATHS` array (e.g. `/mnt/user`, `/mnt/appdata`), `DELETE_MACOS_METADATA` (true/false), `DELETE_WINDOWS_METADATA` (true/false)<br>🔧 **Optional:** `INCLUDE_RESOURCE_FORKS=1` to delete `._*` files |
| **out-of-memory-errors.sh** | Checks syslog for "Out of memory" and sends an Unraid dynamix alert if found. Schedule (e.g. hourly).<br>📝 **Config:** `SYSLOG_PATH` if needed |
| **queue-sync-nzbget.sh** | Syncs Sonarr/Radarr queues with NZBGet: removes \*arr queue entries when the download is gone from NZBGet, blocklists, and triggers search.<br>📝 **Config:** Radarr/Sonarr/NZBGet URLs and API keys/passwords<br>🧪 **Dry-run:** `DRY_RUN=1`<br>⚙️ **Dependencies:** curl, jq |
| **record-disk-assignments.sh** | Writes current Unraid disk assignments to `/boot/config/DISK_ASSIGNMENTS.txt`.<br>📝 **Config:** `OUTPUT_FILE` or `DISKS_INI` to override paths |
| **server-info-push.sh** | Sends a status summary (array/cache/appdata free space, CPU temps, running containers) via Pushover or Pushbullet.<br>📝 **Config:** `PUSH_NOTIFICATIONS` (0/1/2) and the relevant API keys; edit mount paths if needed<br>📬 **Notifications:** Pushover or Pushbullet |
| **update-radarr-profiles.sh** | Updates Radarr quality profiles by year: current year → one profile, previous year → older movies profile.<br>📝 **Config:** `RADARR_URL`, `RADARR_API_KEY`, `CURRENT_YEAR_PROFILE_ID`, `OLDER_MOVIES_PROFILE_ID`, `PROCESS_CURRENT_YEAR` (true/false), `PROCESS_PREVIOUS_YEAR` (true/false)<br>🔧 **Optional:** `CUSTOM_CURRENT_YEAR`, `CUSTOM_PREVIOUS_YEAR` to override auto-detected years<br>🧪 **Dry-run:** `DRY_RUN=1` |
| **view-docker-log-size.sh** | Lists Docker container log file sizes (largest first) to see if logging is filling docker.img.<br>📝 **Config:** `DOCKER_CONTAINERS_PATH` and `HEAD_COUNT` if needed |

## Script format

All scripts in the repository root follow a consistent format:

- A standard header (name, description, usage, configuration, author, license)
- `set -u`
- Configuration variables at the top with “EDIT FOR YOUR SETUP” where needed
- No personal information (use env vars or placeholders for API keys, paths, passwords)
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
- **Dry-run:** `DEBUG=1 ./clean-nzb-junk.sh`
- **Run:** `./clean-nzb-junk.sh`

## Author

[Steven (evenwebb)](https://github.com/evenwebb) · [unraid-user-scripts](https://github.com/evenwebb/unraid-user-scripts)

## License

GNU General Public License v3.0. See [LICENSE](LICENSE) or [https://www.gnu.org/licenses/gpl-3.0.html](https://www.gnu.org/licenses/gpl-3.0.html).

## Contributing

Open issues or pull requests as needed. Test changes before submitting.
