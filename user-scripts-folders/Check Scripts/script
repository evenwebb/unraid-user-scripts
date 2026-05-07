#!/bin/bash
# Run `bash -n` on root *.sh (source of truth) and deployed-style folder scripts.
set -euo pipefail
cd "$(dirname "$0")"

errors=0
count=0

check_one() {
  local f="$1"
  count=$((count + 1))
  printf 'bash -n: %s ... ' "$f"
  if bash -n "$f"; then
    printf 'OK\n'
  else
    printf 'FAIL\n'
    errors=$((errors + 1))
  fi
}

shopt -s nullglob

for sh in *.sh; do
  check_one "$sh"
done

for fs in user-scripts-folders/*/script; do
  check_one "$fs"
done

if (( errors > 0 )); then
  printf >&2 '%d script(s) failed bash -n\n' "$errors"
  exit 1
fi

printf -- '---\nAll %d bash script(s) passed syntax check.\n' "$count"
