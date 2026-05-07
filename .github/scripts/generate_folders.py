#!/usr/bin/env python3
"""
Generate User Scripts plugin folders for Unraid.
Creates a folder structure compatible with the User Scripts plugin.
Only regenerates folders for scripts that have changed.
"""

import shutil
import re
import hashlib
import argparse
import os
import tempfile
from pathlib import Path

# Mapping of script filenames to display names (folder names)
SCRIPT_NAMES = {
    'apply-unraid-perms.sh': 'Apply Unraid Permissions',
    'btrfs-scrub.sh': 'BTRFS Scrub',
    'check-plex-status.sh': 'Check Plex Status',
    'check-smart-status.sh': 'Check SMART Status',
    'clean-docker-log-size.sh': 'Clean Docker Log Size',
    'clean-nzb-junk.sh': 'Clean NZB Junk',
    'clean-torrent-junk.sh': 'Clean Torrent Junk',
    'clear-movies-download-folder.sh': 'Clear Movies Download Folder',
    'clear-plex-codecs.sh': 'Clear Plex Codecs',
    'clear-torrent-download-folder.sh': 'Clear Torrent Download Folder',
    'clear-tv-shows-download-folder.sh': 'Clear TV Shows Download Folder',
    'delete-dangling-images.sh': 'Delete Dangling Images',
    'disk-error-alert.sh': 'Disk Error Alert',
    'remove-os-metadata.sh': 'Remove OS Metadata',
    'out-of-memory-errors.sh': 'Out of Memory Errors',
    'queue-sync-nzbget.sh': 'Queue Sync NZBGet',
    'language-guard-radarr.sh': 'Language Guard - Radarr',
    'record-disk-assignments.sh': 'Record Disk Assignments',
    'server-info-push.sh': 'Server Info Push',
    'language-guard-sonarr.sh': 'Language Guard - Sonarr',
    'user-scripts-updater.sh': 'User Scripts Updater',
    'update-radarr-profiles.sh': 'Update Radarr Profiles',
    'update-sonarr-profiles.sh': 'Update Sonarr Profiles',
    'view-docker-log-size.sh': 'View Docker Log Size',
}

# Mapping of script filenames to descriptions (from README table)
SCRIPT_DESCRIPTIONS = {
    'apply-unraid-perms.sh': 'Applies Unraid-style "new permissions" (nobody:users, Docker-safe) to configured paths.',
    'btrfs-scrub.sh': 'Runs a Btrfs scrub on a cache/device, logs output, and sends Unraid notifications on start/success/failure.',
    'check-plex-status.sh': 'Checks if the Plex Docker container is running and if the web UI responds; restarts the container if the UI is unreachable.',
    'check-smart-status.sh': 'Checks SMART health status of disks and sends an Unraid notification if any fail.',
    'clean-docker-log-size.sh': 'Truncates Docker container log files to free space in docker.img. Shows before/after sizes.',
    'clean-nzb-junk.sh': 'Removes NZB download junk (nfo, par2, samples, RAR splits, etc.) and empty directories.',
    'clean-torrent-junk.sh': 'Removes torrent download junk (nfo, par2, samples, RAR splits, etc.) and empty directories.',
    'clear-movies-download-folder.sh': 'Empties the movies download directory and prints a summary.',
    'clear-plex-codecs.sh': 'Deletes Plex Media Server codec cache (Plex re-downloads as needed).',
    'clear-torrent-download-folder.sh': 'Empties the torrent download directory and prints a summary.',
    'clear-tv-shows-download-folder.sh': 'Empties the TV shows download directory and prints a summary.',
    'delete-dangling-images.sh': 'Removes Docker images with no tag (dangling) to free space in docker.img.',
    'disk-error-alert.sh': 'Checks syslog for md/storage errors and sends an Unraid dynamix alert if found. Schedule (e.g. hourly).',
    'remove-os-metadata.sh': 'Removes macOS metadata files (.DS_Store, ._*, .Spotlight-V100, .Trashes, etc.) and Windows metadata files (Thumbs.db, desktop.ini, etc.).',
    'out-of-memory-errors.sh': 'Checks syslog for "Out of memory" and sends an Unraid dynamix alert if found. Schedule (e.g. hourly).',
    'queue-sync-nzbget.sh': 'Syncs Sonarr/Radarr queues with NZBGet: removes *arr queue entries when the download is gone from NZBGet, blocklists, and triggers search.',
    'language-guard-radarr.sh': 'Audits Radarr movie files for acceptable audio languages and remediates bad releases by blocklisting, deleting, and re-searching.',
    'record-disk-assignments.sh': 'Writes current Unraid disk assignments to /boot/config/DISK_ASSIGNMENTS.txt.',
    'server-info-push.sh': 'Sends a status summary (array/cache/appdata free space, CPU temps, running containers) via Unraid dynamix notify.',
    'language-guard-sonarr.sh': 'Audits Sonarr episode files for acceptable audio languages and remediates bad releases by blocklisting, deleting, and re-searching.',
    'user-scripts-updater.sh': 'Updates Unraid User Scripts folders from GitHub while preserving local config edits during upgrades.',
    'update-radarr-profiles.sh': 'Updates Radarr quality profiles by year: current year → one profile, previous year → older movies profile.',
    'update-sonarr-profiles.sh': 'Updates Sonarr quality profiles by show status: airing, upcoming, ended, continuing with no upcoming.',
    'view-docker-log-size.sh': 'Lists Docker container log file sizes (largest first) to see if logging is filling docker.img.',
}


def sanitize_folder_name(name):
    """Sanitize folder name for User Scripts plugin (only allow letters, digits, hyphens, underscores, colons, periods, spaces)."""
    # Remove any characters that aren't allowed
    sanitized = re.sub(r'[^A-Za-z0-9\-_:. ]', '', name)
    return sanitized.strip()


def parse_readme_descriptions():
    """Parse README.md to extract script descriptions dynamically."""
    readme_path = Path('README.md')
    if not readme_path.exists():
        return {}
    
    descriptions = {}
    with open(readme_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Match table rows: | **script.sh** | Description... |
    pattern = r'\|\s+\*\*([^\*]+\.sh)\*\*\s+\|\s+([^\|]+(?:\<br\>[^\|]+)*)'
    matches = re.findall(pattern, content)
    
    for script_file, desc_html in matches:
        # Remove HTML tags and clean up
        desc = re.sub(r'<[^>]+>', '', desc_html)
        desc = desc.strip()
        # Remove config notes and emojis for cleaner description
        desc = re.sub(r'📝.*$', '', desc, flags=re.MULTILINE)
        desc = re.sub(r'📬.*$', '', desc, flags=re.MULTILINE)
        desc = re.sub(r'🧪.*$', '', desc, flags=re.MULTILINE)
        desc = re.sub(r'⚙️.*$', '', desc, flags=re.MULTILINE)
        desc = re.sub(r'🔧.*$', '', desc, flags=re.MULTILINE)
        desc = re.sub(r'✅.*$', '', desc, flags=re.MULTILINE)
        # Clean up markdown escape sequences for plain text display
        desc = desc.replace(r'\*', '*')  # Unescape asterisks
        desc = desc.replace(r'\_', '_')   # Unescape underscores
        desc = desc.strip()
        descriptions[script_file] = desc
    
    return descriptions


def get_file_hash(file_path):
    """Get SHA256 hash of file content (optimized for large files)."""
    if not file_path.exists():
        return None
    sha256 = hashlib.sha256()
    with open(file_path, 'rb') as f:
        # Read in chunks to handle large files efficiently
        for chunk in iter(lambda: f.read(8192), b''):
            sha256.update(chunk)
    return sha256.hexdigest()


def atomic_write_text(dest_path: Path, content: str) -> None:
    """Write text atomically to avoid truncated output on interruption."""
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{dest_path.name}.tmp.", dir=dest_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        Path(tmp_name).replace(dest_path)
    except Exception:
        Path(tmp_name).unlink(missing_ok=True)
        raise


def is_safe_generated_folder(folder_path: Path, output_dir: Path) -> bool:
    """Only allow deleting direct child folders inside the generated output directory."""
    try:
        return folder_path.parent.resolve() == output_dir.resolve() and folder_path.is_dir()
    except FileNotFoundError:
        return False


def main():
    parser = argparse.ArgumentParser(description="Generate Unraid User Scripts plugin folders.")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without writing or deleting files.")
    args = parser.parse_args()

    repo_root = Path('.')
    output_dir = repo_root / 'user-scripts-folders'
    
    # Create output directory if it doesn't exist
    output_dir.mkdir(exist_ok=True)
    
    # Parse descriptions from README (fallback to hardcoded if parsing fails)
    readme_descriptions = parse_readme_descriptions()
    
    # Get all .sh files in root
    script_files = sorted(repo_root.glob('*.sh'))
    
    if not script_files:
        print("No .sh files found in root directory")
        return
    
    print(f"Found {len(script_files)} scripts")
    
    # Track which scripts exist
    existing_folders = set()
    updated_count = 0
    skipped_count = 0
    removed_count = 0
    failed_count = 0
    
    script_hashes = {}
    for script_path in script_files:
        script_hashes[script_path.name] = get_file_hash(script_path)
    
    for script_path in script_files:
        script_file = script_path.name
        
        # Get display name (auto-generate for new scripts not in mapping)
        display_name = SCRIPT_NAMES.get(script_file, script_file.replace('.sh', '').replace('-', ' ').title())
        
        # Get description (prefer README parsed, fallback to hardcoded)
        description = readme_descriptions.get(script_file, SCRIPT_DESCRIPTIONS.get(script_file, 'Unraid user script'))
        
        # Sanitize folder name (folder name can differ from display name)
        # Unraid User Scripts shows the friendly name from the `name` file, so we
        # can keep that (e.g. "Language Guard - Radarr") while using a simpler
        # folder name (e.g. "Language Guard Radarr") for nicer sorting.
        folder_name = sanitize_folder_name(display_name.replace(" - ", " "))
        folder_path = output_dir / folder_name
        existing_folders.add(folder_name)

        script_file_path = folder_path / 'script'
        new_script_hash = script_hashes[script_file]
        existing_script_hash = get_file_hash(script_file_path)

        # Check if update is needed
        if not folder_path.exists():
            needs_regenerate, reason = True, "new script"
        elif existing_script_hash != new_script_hash:
            needs_regenerate, reason = True, "script changed"
        else:
            # Only check name/description if script hasn't changed
            name_file_path = folder_path / 'name'
            desc_file_path = folder_path / 'description'
            needs_regenerate = False
            
            if name_file_path.exists():
                with open(name_file_path, 'r', encoding='utf-8') as f:
                    if f.read().strip() != display_name:
                        needs_regenerate, reason = True, "name changed"
            if not needs_regenerate and desc_file_path.exists():
                with open(desc_file_path, 'r', encoding='utf-8') as f:
                    if f.read().strip() != description:
                        needs_regenerate, reason = True, "description changed"
            
            if not needs_regenerate:
                reason = None
        
        if needs_regenerate:
            with open(script_path, 'r', encoding='utf-8') as f:
                script_content = f.read()
        
        if needs_regenerate:
            # Create folder if it doesn't exist
            try:
                if args.dry_run:
                    print(f"~ Would update folder: {folder_name} ({reason})")
                else:
                    folder_path.mkdir(exist_ok=True)
                    script_file_path = folder_path / 'script'
                    atomic_write_text(script_file_path, script_content)

                    name_file_path = folder_path / 'name'
                    atomic_write_text(name_file_path, display_name)

                    desc_file_path = folder_path / 'description'
                    atomic_write_text(desc_file_path, description)

                    print(f"✓ Updated folder: {folder_name} ({reason})")
                updated_count += 1
            except Exception as exc:
                print(f"✗ Failed folder: {folder_name} ({reason}) - {exc}")
                failed_count += 1
        else:
            print(f"⊘ Skipped folder: {folder_name} (no changes)")
            skipped_count += 1
    
    # Remove folders for scripts that no longer exist
    if output_dir.exists():
        for folder_path in output_dir.iterdir():
            if folder_path.is_dir() and folder_path.name not in existing_folders:
                if not is_safe_generated_folder(folder_path, output_dir):
                    print(f"✗ Skipped unsafe folder removal: {folder_path}")
                    failed_count += 1
                    continue
                try:
                    if args.dry_run:
                        print(f"~ Would remove folder: {folder_path.name} (script deleted)")
                    else:
                        shutil.rmtree(folder_path)
                        print(f"✗ Removed folder: {folder_path.name} (script deleted)")
                    removed_count += 1
                except Exception as exc:
                    print(f"✗ Failed to remove folder: {folder_path.name} - {exc}")
                    failed_count += 1
    
    mode_label = "DRY-RUN summary" if args.dry_run else "Summary"
    print(f"\n{mode_label}: {updated_count} updated, {skipped_count} skipped, {removed_count} removed, {failed_count} failed, {len(existing_folders)} total folders")
    print(f"\nGenerated User Scripts plugin folders in {output_dir}/")
    print("\nTo use:")
    print("1. Copy the folders from user-scripts-folders/ to /boot/config/plugins/user.scripts/scripts/ on your Unraid flash drive")
    print("2. The scripts will appear in the User Scripts plugin with their names and descriptions")
    print("3. Edit configuration in each script's 'script' file as needed")


if __name__ == '__main__':
    main()
