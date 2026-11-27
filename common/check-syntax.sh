#!/usr/bin/env bash
# common/check-syntax.sh — bash -n on every script, shellcheck when available.
# Used by `pixi run lint` (shellcheck comes from the pixi environment).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mapfile -t SCRIPTS < <(find bin lib common os -type f \( -name '*.sh' -o -name sys \) | sort)
rc=0
for f in "${SCRIPTS[@]}"; do
  bash -n "$f" || { echo "syntax error: $f" >&2; rc=1; }
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -P lib "${SCRIPTS[@]}" || rc=1
else
  echo "shellcheck not found: only 'bash -n' was run (pixi install provides it)" >&2
fi
[[ $rc -eq 0 ]] && echo "ok: ${#SCRIPTS[@]} scripts"
exit $rc
