<div align="center">

# Unraid User Scripts

**Bash automation for the Unraid [User Scripts](https://unraid.net/community/apps) plugin**

[![GitHub stars](https://img.shields.io/github/stars/evenwebb/unraid-user-scripts?style=flat&logo=github&logoColor=white&label=Stars)](https://github.com/evenwebb/unraid-user-scripts/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/evenwebb/unraid-user-scripts?style=flat&logo=github&logoColor=white&label=Forks)](https://github.com/evenwebb/unraid-user-scripts/network/members)
[![CI](https://img.shields.io/github/actions/workflow/status/evenwebb/unraid-user-scripts/bash-syntax-check.yml?branch=main&style=flat&logo=githubactions&logoColor=white&label=CI)](.github/workflows/bash-syntax-check.yml)
[![Last commit](https://img.shields.io/github/last-commit/evenwebb/unraid-user-scripts?style=flat&logo=git&logoColor=white&label=Last%20commit)](https://github.com/evenwebb/unraid-user-scripts/commits/main)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat&logo=gnu&logoColor=white)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Scripts](https://img.shields.io/badge/Scripts-28-F26F21?style=flat&logo=linuxcontainers&logoColor=white)](https://github.com/evenwebb/unraid-user-scripts/tree/main)
[![Unraid](https://img.shields.io/badge/Unraid-User%20Scripts-F26F21?style=flat&logo=unraid&logoColor=white)](https://unraid.net/community/apps)

[Install](#-installation) · [Scripts](#-scripts) · [Updater](#-user-scripts-updater) · [Contributing](#-contributing)

</div>

> **Quick start:** Copy [`user-scripts-folders/`](user-scripts-folders/) to `/boot/config/plugins/user.scripts/scripts/` on flash.

---

## 🔄 User Scripts Updater

> [`user-scripts-updater.sh`](user-scripts-updater.sh) pulls GitHub updates **without overwriting your config**.

| | |
|---|---|
| **Fetch** | Repo ZIP (no `git` on Unraid) |
| **Default** | Installed scripts only (`INSTALL_MISSING=1` for new ones) |
| **Safety** | Config merge, backups, `bash -n` before write |

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
| **queue-sync-nzbget.sh** | Sync *arr queues with NZBGet: remove stale items, blocklist, re-search |
| **language-guard-radarr.sh** | Audit movie audio languages; remediate via blocklist + re-search |
| **language-guard-sonarr.sh** | Same for Sonarr episodes |
| **update-radarr-profiles.sh** | Assign quality profiles by movie year |
| **update-sonarr-profiles.sh** | Assign quality profiles by show status |

### Downloads · cleanup

| Script | Description |
|:-------|:------------|
| **clean-download-junk.sh** | Remove NZB/torrent junk; profiles: `nzb`, `torrent`, `all`, `custom` |
| **clean-nzb-junk.sh** | Legacy; use **clean-download-junk.sh** (`PROFILE=nzb`) |
| **clean-torrent-junk.sh** | Legacy; use **clean-download-junk.sh** (`PROFILE=torrent`) |
| **clear-movies-download-folder.sh** | Empty movies download folder (optional age filter) |
| **clear-torrent-download-folder.sh** | Empty torrent download folder (optional age filter) |
| **clear-tv-shows-download-folder.sh** | Empty TV download folder (optional age filter) |
| **remove-os-metadata.sh** | Remove `.DS_Store`, `Thumbs.db`, and similar metadata |

### Docker · Plex

| Script | Description |
|:-------|:------------|
| **check-plex-status.sh** | Check Plex container + web UI; restart if down |
| **clear-plex-codecs.sh** | Clear Plex codec cache |
| **clean-docker-log-size.sh** | Truncate container logs (free docker.img space) |
| **delete-dangling-images.sh** | Remove untagged Docker images |
| **docker-image-usage-alert.sh** | Alert on docker.img usage (default 70% / 85%) |
| **view-docker-log-size.sh** | List largest container logs |

### Array · disks · parity

| Script | Description |
|:-------|:------------|
| **apply-unraid-perms.sh** | Apply Unraid permissions (nobody:users); requires root |
| **btrfs-scrub.sh** | Btrfs scrub with notifications |
| **check-smart-status.sh** | SMART health alert; requires root |
| **disk-error-alert.sh** | Alert on new md/storage syslog errors |
| **flash-backup.sh** | Flash drive backups to array (rotation + verify) |
| **out-of-memory-errors.sh** | Alert on new OOM syslog events |
| **parity-check-monitor.sh** | Parity check progress notifications |
| **record-disk-assignments.sh** | Export disk assignments to flash |

### Server · misc

| Script | Description |
|:-------|:------------|
| **server-info-push.sh** | Push server status summary via notify |
| **user-scripts-updater.sh** | Update plugin folders from GitHub (see [Updater](#-user-scripts-updater)) |

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
