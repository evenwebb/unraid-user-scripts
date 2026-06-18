#!/usr/bin/env python3
"""Verify root *.sh match user-scripts-folders/*/script copies (both directions)."""
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
folders = root / "user-scripts-folders"

root_scripts = sorted(root.glob("*.sh"))
mapping = {}
for d in sorted(folders.iterdir()):
    if not d.is_dir() or d.name.startswith("_"):
        continue
    script = d / "script"
    if not script.is_file():
        print(f"ORPHAN folder (no script file): {d.name}")
        continue
    for line in script.read_text(encoding="utf-8").splitlines()[:5]:
        if line.startswith("# ") and line.endswith(".sh"):
            sh_name = line[2:].strip()
            if sh_name in mapping:
                print(f"DUPLICATE mapping: {sh_name} in {mapping[sh_name].parent.name} and {d.name}")
                sys.exit(1)
            mapping[sh_name] = script
            break
    else:
        print(f"ORPHAN folder (no # script.sh header): {d.name}")

missing = [sh.name for sh in root_scripts if sh.name not in mapping]
extra = sorted(set(mapping) - {s.name for s in root_scripts})
mismatch = [
    sh.name for sh in root_scripts
    if sh.name in mapping and sh.read_text(encoding="utf-8") != mapping[sh.name].read_text(encoding="utf-8")
]

print(f"mapped: {len(mapping)} folders, root scripts: {len(root_scripts)}")
if missing:
    print("MISSING folder mapping:", ", ".join(missing))
if extra:
    print("EXTRA folders without root script:", ", ".join(extra))
if mismatch:
    print("MISMATCH:", ", ".join(mismatch))

if missing or extra or mismatch or len(root_scripts) != len(mapping):
    sys.exit(1)
print("all root scripts match user-scripts-folders copies")
sys.exit(0)
