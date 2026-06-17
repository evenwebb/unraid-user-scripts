#!/usr/bin/env bash
# Run bash -n on root *.sh and user-scripts-folders/*/script copies.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

errors=0
count=0

for sh in *.sh; do
  [[ -f "$sh" ]] || continue
  count=$((count + 1))
  echo "bash -n: $sh ..."
  bash -n "$sh" || errors=$((errors + 1))
done

shopt -s nullglob
for fs in user-scripts-folders/*/script; do
  count=$((count + 1))
  echo "bash -n: $fs ..."
  bash -n "$fs" || errors=$((errors + 1))
done
shopt -u nullglob

if [[ "$errors" -ne 0 ]]; then
  echo "--- $errors of $count script(s) failed bash -n."
  exit 1
fi

echo "--- All $count script(s) passed bash -n."
