<div align="center">

# Unraid User Scripts

**Bash automation for the Unraid [User Scripts](https://unraid.net/community/apps) plugin**

[![GitHub stars](https://img.shields.io/github/stars/evenwebb/unraid-user-scripts?style=flat&logo=github&logoColor=white&label=Stars)](https://github.com/evenwebb/unraid-user-scripts/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/evenwebb/unraid-user-scripts?style=flat&logo=github&logoColor=white&label=Forks)](https://github.com/evenwebb/unraid-user-scripts/network/members)
[![CI](https://img.shields.io/github/actions/workflow/status/evenwebb/unraid-user-scripts/bash-syntax-check.yml?branch=main&style=flat&logo=githubactions&logoColor=white&label=CI)](.github/workflows/bash-syntax-check.yml)
[![Last commit](https://img.shields.io/github/last-commit/evenwebb/unraid-user-scripts?style=flat&logo=git&logoColor=white&label=Last%20commit)](https://github.com/evenwebb/unraid-user-scripts/commits/main)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat&logo=gnu&logoColor=white)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Scripts](https://img.shields.io/badge/Scripts-26-F26F21?style=flat&logo=linuxcontainers&logoColor=white)](https://github.com/evenwebb/unraid-user-scripts/tree/main)
[![Unraid](https://img.shields.io/badge/Unraid-User%20Scripts-F26F21?style=flat&logo=unraid&logoColor=white)](https://unraid.net/community/apps)

[Install](#-installation) · [Scripts](#-scripts) · [Updater](#-user-scripts-updater) · [Contributing](#-contributing)

</div>

> **Quick start:** Copy [`user-scripts-folders/`](user-scripts-folders/) to `/boot/config/plugins/user.scripts/scripts/` on flash.

---

## 🔄 User Scripts Updater

> [`user-scripts-updater.sh`](user-scripts-updater.sh) pulls GitHub updates **without overwriting your config**.

First run: `DRY_RUN=1` → review → `DRY_RUN=0` and schedule.

---

## 🚀 Installation

<details>
<summary>Paste into User Scripts (Web UI)</summary>

1. Install **User Scripts** from Community Applications
2. **Settings → User Scripts → Add New Script**
3. Paste a script from this repo, edit config, save, run or schedule

</details>

<details open>
<summary>Copy plugin folders (recommended)</summary>

One folder per script under `/boot/config/plugins/user.scripts/scripts/` (`script`, `name`, `description`).

1. Copy [`user-scripts-folders/`](user-scripts-folders/) to flash `scripts/`
2. Edit config in each `script` file
3. Run or schedule in the plugin

Folders [auto-sync on push to `main`](.github/workflows/sync-user-scripts-folders.yml). Regenerate: `python3 .github/scripts/generate_folders.py`

</details>

---

## 📜 Scripts

### Media · Sonarr · Radarr · NZBGet

| Script | Description |
|:-------|:------------|
| **queue-sync-nzbget.sh** | Remove stale *arr queue items when NZBGet lost the download |
| **language-guard-radarr.sh** | Fix Radarr movies with wrong audio language |
| **language-guard-sonarr.sh** | Fix Sonarr episodes with wrong audio language |
| **update-radarr-profiles.sh** | Set Radarr quality profiles by movie release year |
| **update-sonarr-profiles.sh** | Set Sonarr quality profiles by series airing status |

### Downloads · cleanup

| Script | Description |
|:-------|:------------|
| **clean-download-junk.sh** | Delete leftover download files and empty folders |
| **clear-movies-download-folder.sh** | Clear movies download folder; optional age filter |
| **clear-torrent-download-folder.sh** | Clear torrent download folder; optional age filter |
| **clear-tv-shows-download-folder.sh** | Clear TV download folder; optional age filter |
| **remove-os-metadata.sh** | Remove .DS_Store, Thumbs.db, and OS metadata |

### Docker · Plex

| Script | Description |
|:-------|:------------|
| **check-plex-status.sh** | Restart Plex when the web UI stops responding |
| **clear-plex-codecs.sh** | Clear Plex codec cache to free space |
| **clean-docker-log-size.sh** | Truncate oversized Docker logs |
| **delete-dangling-images.sh** | Remove untagged Docker images |
| **docker-image-usage-alert.sh** | Warn at 70% docker.img; alert at 85% |
| **view-docker-log-size.sh** | Show largest container logs |

### Array · disks · parity

| Script | Description |
|:-------|:------------|
| **apply-unraid-perms.sh** | Fix share permissions for Unraid and Docker; requires root |
| **btrfs-scrub.sh** | Run Btrfs scrub with start/finish/failure notifications |
| **check-smart-status.sh** | Notify on SMART disk failures; requires root |
| **disk-error-alert.sh** | Notify on new disk or array syslog errors |
| **flash-backup.sh** | Back up USB flash to the array with rotation |
| **out-of-memory-errors.sh** | Notify when the OOM killer stops a process |
| **parity-check-monitor.sh** | Notify during parity checks |
| **record-disk-assignments.sh** | Save disk slot assignments to flash |

### Server · misc

| Script | Description |
|:-------|:------------|
| **server-info-push.sh** | Notification with space, temps, load, VMs, and containers |
| **user-scripts-updater.sh** | Update all User Scripts from GitHub; keeps your settings |

---

## 📦 Dependencies

| Dependency | Scripts |
|:-----------|:--------|
| curl + jq | `queue-sync-nzbget.sh`, `language-guard-*.sh`, `update-*-profiles.sh` |
| python3 | `language-guard-*.sh` |
| Docker CLI | `check-plex-status.sh`, `clean-docker-log-size.sh`, `delete-dangling-images.sh`, `docker-image-usage-alert.sh`, `view-docker-log-size.sh` |
| Bash 4.3+ | `user-scripts-updater.sh` |
| root / sudo | `apply-unraid-perms.sh`, `check-smart-status.sh` |
| smartctl | `check-smart-status.sh`; optional in `disk-error-alert.sh` |

---

<div align="center">

**[Steven (evenwebb)](https://github.com/evenwebb)** · [GPL-3.0](LICENSE)

PRs welcome · [CI](.github/workflows/bash-syntax-check.yml) on pull requests · `user-scripts-folders/` [auto-synced](.github/workflows/sync-user-scripts-folders.yml) on merge to `main`

New scripts: update this README and [generate_folders.py](.github/scripts/generate_folders.py)

</div>
