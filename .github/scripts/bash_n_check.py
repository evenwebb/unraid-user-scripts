#!/usr/bin/env python3
import glob
import subprocess
import sys

root = __import__("pathlib").Path(__file__).resolve().parents[2]
failed = []
for path in sorted(root.glob("*.sh")):
    r = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    if r.returncode:
        failed.append((path.name, r.stderr.strip()))
if failed:
    for name, err in failed:
        print(f"FAIL {name}: {err}")
    sys.exit(1)
print(f"OK: {len(list(root.glob('*.sh')))} scripts")
