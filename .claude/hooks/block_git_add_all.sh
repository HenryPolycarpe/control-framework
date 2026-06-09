#!/usr/bin/env bash
# PreToolUse hook — blocks blanket `git add -A` / `git add --all` / `git add .` in the control repo.
# Reason: blanket staging once swept in foreign files (incl. a private SSH key) by accident.
# Fix: stage individual paths. This hook is deterministic (unlike an advisory CLAUDE.md rule).
#
# Input:  PreToolUse JSON via stdin (tool_name, tool_input.command).
# Output: on match, JSON with permissionDecision=deny; otherwise nothing (allow).
set -euo pipefail

INPUT="$(cat)"
CMD=$(printf '%s' "$INPUT" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))
except Exception:
    print('')" 2>/dev/null || echo "")

# Match: 'git add' followed by -A / --all / '.' (whole-tree staging)
if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+add[[:space:]]+(-A\b|--all\b|\.([[:space:]]|$))'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"`git add -A` / `git add .` is blocked in this repo (blanket staging once swept in foreign files incl. a private SSH key). Stage explicitly: `git add <path1> <path2> ...`."}}
EOF
  exit 0
fi
exit 0
