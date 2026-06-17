#!/usr/bin/env python3
"""Verify root *.sh match user-scripts-folders/*/script copies."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
folders = root / "user-scripts-folders"
mapping = {}
for d in sorted(folders.iterdir()):
    script = d / "script"
    if not script.is_file():
        continue
    # folder name doesn't map 1:1 to sh name; match by shebang line 3 (# name.sh)
    first = script.read_text(encoding="utf-8").splitlines()
    for line in first[:5]:
        if line.startswith("# ") and line.endswith(".sh"):
            mapping[line[2:].strip()] = script
            break

missing = []
mismatch = []
for sh in sorted(root.glob("*.sh")):
    copy = mapping.get(sh.name)
    if not copy:
        missing.append(sh.name)
        continue
    if sh.read_text(encoding="utf-8") != copy.read_text(encoding="utf-8"):
        mismatch.append(sh.name)

print(f"mapped: {len(mapping)} folders")
if missing:
    print("MISSING folder mapping:", ", ".join(missing))
if mismatch:
    print("MISMATCH:", ", ".join(mismatch))
else:
    print("all root scripts match user-scripts-folders copies")
if not missing and not mismatch:
    raise SystemExit(0)
raise SystemExit(1)
