#!/usr/bin/env bash
# 純粋 Lua モジュールのユニットテストを実行する (wezterm 不要 / lua 5.3+)
set -u
cd "$(dirname "$0")/.."

if ! command -v lua > /dev/null 2>&1; then
  echo "error: lua interpreter not found (brew install lua)" >&2
  exit 1
fi

status=0
for spec in tests/*_spec.lua; do
  if ! lua "$spec"; then
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "all specs passed"
else
  echo "some specs FAILED" >&2
fi
exit "$status"
