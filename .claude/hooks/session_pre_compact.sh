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
# CONTROL_DIR auto-detected from this script's location (.claude/hooks/ -> repo root). Override w/ CTRL_HOME.
set -uo pipefail

CONTROL_DIR="${CTRL_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SNAP_DIR="$CONTROL_DIR/.session_snapshots"
LOG_FILE="$CONTROL_DIR/.claude/hooks/session_pre_compact.log"
mkdir -p "$SNAP_DIR" 2>/dev/null

INPUT="$(cat)"
get(){ printf '%s' "$INPUT" | grep -o "\"$1\"[^,}]*" | sed "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/" | head -1; }

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
