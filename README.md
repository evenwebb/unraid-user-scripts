<div align="center">

# Unraid User Scripts

**Bash automation for the Unraid [User Scripts](https://unraid.net/community/apps) plugin**

[![GitHub stars](https://img.shields.io/github/stars/evenwebb/unraid-user-scripts?style=flat&logo=github&logoColor=white&label=Stars)](https://github.com/evenwebb/unraid-user-scripts/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/evenwebb/unraid-user-scripts?style=flat&logo=github&logoColor=white&label=Forks)](https://github.com/evenwebb/unraid-user-scripts/network/members)
[![CI](https://img.shields.io/github/actions/workflow/status/evenwebb/unraid-user-scripts/bash-syntax-check.yml?branch=main&style=flat&logo=githubactions&logoColor=white&label=CI)](.github/workflows/bash-syntax-check.yml)
[![Last commit](https://img.shields.io/github/last-commit/evenwebb/unraid-user-scripts?style=flat&logo=git&logoColor=white&label=Last%20commit)](https://github.com/evenwebb/unraid-user-scripts/commits/main)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat&logo=gnu&logoColor=white)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Scripts](https://img.shields.io/badge/Scripts-27-F26F21?style=flat&logo=linuxcontainers&logoColor=white)](https://github.com/evenwebb/unraid-user-scripts/tree/main)
[![Unraid](https://img.shields.io/badge/Unraid-User%20Scripts-F26F21?style=flat&logo=unraid&logoColor=white)](https://unraid.net/community/apps)

[Install](#-installation) · [Scripts](#-scripts) · [Updater](#-user-scripts-updater) · [Contributing](#-contributing)

</div>

If you run **Unraid** at home, the [User Scripts](https://unraid.net/community/apps) plugin is a simple way to run bash tasks from the web UI - scheduled cleanups, health checks, API syncs, and notifications without living in SSH. This repository is a collection of scripts I wrote for my own server and shared here: keeping Sonarr, Radarr, and NZBGet queues aligned, clearing download folders safely, watching disk and parity health, backing up flash, trimming Docker, and updating installed scripts while keeping your local settings.

Each script is a single self-contained file. Copy the ready-made plugin folders to your flash drive, or paste a script into the User Scripts editor, change the variables in the **EDIT FOR YOUR SETUP** section at the top, then run once or put it on a schedule.

> **Quick start:** Copy [`user-scripts-folders/`](user-scripts-folders/) to `/boot/config/plugins/user.scripts/scripts/` on flash.

---

## 🔄 User Scripts Updater

> [`user-scripts-updater.sh`](user-scripts-updater.sh) pulls GitHub updates **without overwriting your config**. On a live run (`DRY_RUN=0`), it updates itself first if needed, re-launches with the new version, then syncs all other scripts.

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
| **clear-plex-codecs.sh** | Clear Plex codec cache; optional container restart |
| **clean-docker-log-size.sh** | Truncate oversized Docker logs |
| **delete-dangling-images.sh** | Remove untagged Docker images |
| **docker-image-usage-alert.sh** | Warn at 70% docker.img; alert at 85% |
| **unraid-path-guard.sh** | Monitor unexpected shares, risky Docker paths, and watched folders |
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
| **parity-check-monitor.sh** | Track parity-check progress and report start, completion, interruption, and errors |
| **record-disk-assignments.sh** | Save disk slot assignments to flash |

### Server · misc

| Script | Description |
|:-------|:------------|
| **server-info-push.sh** | Notification with space, temps, load, VMs, and containers |
| **user-scripts-updater.sh** | Update all User Scripts from GitHub; keeps your settings |

### Unraid Path Guard

`unraid-path-guard.sh` only reports findings; it does not change shares, folders, files, or Docker. Before scheduling it, review the settings at the top of the script: defaults assume appdata is mounted at `/mnt/appdata`, Docker data is under `/mnt/appdata/docker`, and `/mnt/user/appdata` is unwanted. The first run records current folder baselines in `STATE_DIR`; `--accept-current` replaces those snapshots when run manually.

---

## 📦 Dependencies

| Dependency | Scripts |
|:-----------|:--------|
| curl + jq | `queue-sync-nzbget.sh`, `language-guard-*.sh`, `update-*-profiles.sh` |
| Python 3 | `language-guard-*.sh` (not included in Unraid OS by default; install a compatible Python 3 plugin such as Python 3 for UNRAID) |
| Docker CLI | `check-plex-status.sh`, `clear-plex-codecs.sh` (if restart enabled), `clean-docker-log-size.sh`, `delete-dangling-images.sh`, `docker-image-usage-alert.sh`, `view-docker-log-size.sh`; optional container inspection in `unraid-path-guard.sh` |
| PHP CLI with SimpleXML | Optional saved-template inspection in `unraid-path-guard.sh` |
| mountpoint | `unraid-path-guard.sh` |
| Bash 4.3+ | `user-scripts-updater.sh`, `unraid-path-guard.sh` |
| unzip, curl, md5sum | `user-scripts-updater.sh` (zip mode) |
| flock | `queue-sync-nzbget.sh`, `user-scripts-updater.sh`, `docker-image-usage-alert.sh`, `flash-backup.sh` (when `LOCK_FILE` set), `parity-check-monitor.sh`; optional overlap protection in `unraid-path-guard.sh` |
| root / sudo | `apply-unraid-perms.sh`, `check-smart-status.sh`, `btrfs-scrub.sh`, `unraid-path-guard.sh` |
| smartctl | `check-smart-status.sh`; required when `disk-error-alert.sh` `ENABLE_SMART_CORRELATION=1` |

---

## 🤝 Contributing

1. Edit scripts in the repo root (`*.sh`), not only `user-scripts-folders/`.
2. Run `python3 .github/scripts/generate_folders.py` and commit `user-scripts-folders/`.
3. CI runs `bash -n`, verifies generated copies, and runs the Path Guard integration test.
4. Test scripts on Unraid manually with safe settings before scheduling; Path Guard is monitor-only.

**Compatibility review:** Unraid 7.3.3 is the current stable release; 7.4.0-rc.1 is a test release. Scripts use Bash 4+ and standard Unraid utilities, with optional/plugin dependencies listed above. Python 3 is an external prerequisite for the language guards. The parity monitor reads `/var/local/emhttp/var.ini` fields rather than the newer API; this has not been validated against a live 7.x server. The repository has not been runtime-tested on Unraid 7.3.3 or 7.4.0-rc.1.

---

<div align="center">

**[Steven (evenwebb)](https://github.com/evenwebb)** · [GPL-3.0](LICENSE)

PRs welcome · [CI](.github/workflows/bash-syntax-check.yml) on pull requests · `user-scripts-folders/` [auto-synced](.github/workflows/sync-user-scripts-folders.yml) on merge to `main`

New scripts: update this README and [generate_folders.py](.github/scripts/generate_folders.py)

</div>
