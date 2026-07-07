#!/usr/bin/env bash
# PreCompact hook — snapshots the FULL transcript BEFORE Claude Code compacts it.
#
# Why: when a session hits the context limit, Claude Code truncates the history. By the time SessionEnd
# fires, the transcript is already the compacted (lossy) version. PreCompact runs just before that, so
# this is the richest capture of the session. We always allow compaction to proceed (exit 0) — this hook
# only preserves data, it never blocks.
#
# PreCompact cannot inject context (it has no additionalContext channel — only blocking). So this is a
# pure side-effect: write the snapshot, log, exit 0. The SessionEnd hook is paired with a no-clobber
# guard so it won't overwrite this richer snapshot with the post-compaction transcript.
#
# Input:  hook JSON via stdin (session_id, transcript_path, trigger=manual|auto).
# CONTROL_DIR is auto-detected from this script's location (.claude/hooks/ -> repo root).
# Override with CTRL_HOME (isolated tests) or rely on CLAUDE_PROJECT_DIR.
set -uo pipefail

CONTROL_DIR="${CTRL_HOME:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
SNAP_DIR="$CONTROL_DIR/.session_snapshots"
LOG_FILE="$CONTROL_DIR/.claude/hooks/session_pre_compact.log"
mkdir -p "$SNAP_DIR" 2>/dev/null

INPUT="$(cat)"
# Robust: real JSON parsing via python3 (handles escapes/null/format variants). Fallback: grep/sed.
get(){
  local v
  if command -v python3 >/dev/null 2>&1; then
    v=$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
v = d.get(sys.argv[1], "")
sys.stdout.write(v if isinstance(v, str) else "")
' "$1" 2>/dev/null) && { printf '%s' "$v"; return 0; }
  fi
  printf '%s' "$INPUT" | grep -o "\"$1\"[^,}]*" | sed "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/" | head -1
}

SESSION_ID="$(get session_id)"
[ -z "$SESSION_ID" ] && SESSION_ID="unknown-$(date -u +%s)"
TRANSCRIPT="$(get transcript_path)"
TRIGGER="$(get trigger)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Snapshot the pre-compaction transcript. Overwrite: the latest pre-compaction state is the richest
# (a session may compact several times; the most recent capture before the final compaction wins).
SNAP=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if cp "$TRANSCRIPT" "$SNAP_DIR/$SESSION_ID.jsonl" 2>/dev/null; then
    SNAP="$SNAP_DIR/$SESSION_ID.jsonl"
  fi
fi

echo "$TS pre_compact: id=$SESSION_ID trigger=$TRIGGER snapshot=${SNAP:-NONE}" >> "$LOG_FILE" 2>/dev/null
exit 0
