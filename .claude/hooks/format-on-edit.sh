#!/usr/bin/env bash
# PostToolUse hook: auto-format files after agent edits.

set -euo pipefail

file="${CLAUDE_FILE_PATH:-}"
if [[ -z "$file" || ! -f "$file" ]]; then
  exit 0
fi

case "$file" in
  *.go)
    gofmt -w "$file"
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      ruff format "$file"
    elif command -v uvx >/dev/null 2>&1; then
      uvx ruff format "$file"
    fi
    ;;
esac

exit 0
