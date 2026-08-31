#!/usr/bin/env bash
# PreToolUse hook: block destructive shell commands before execution.
# Exit 0 = allow, exit 2 = block.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input', {}).get('command', ''))" 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

if echo "$COMMAND" | grep -qE 'rm[[:space:]]+-[a-zA-Z]*f[[:space:]]+(/|~|\$HOME|[*])'; then
  echo "BLOCKED: destructive rm -rf on system or broad paths."
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]].*(-f|--force)'; then
  echo "BLOCKED: force push is not allowed."
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]]+(origin[[:space:]]+)?(main|master)\b'; then
  echo "BLOCKED: direct push to main/master is not allowed."
  exit 2
fi

if echo "$COMMAND" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard'; then
  echo "BLOCKED: git reset --hard can discard uncommitted work."
  exit 2
fi

exit 0
