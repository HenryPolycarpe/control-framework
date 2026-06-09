#!/usr/bin/env bash
# SessionEnd hook — drops one per-session flag into a folder + snapshots the transcript immediately.
# Fixes: single-file-flag race (overwrite on fast back-to-back sessions) + transcript-gone-when-consumed.
#
# Input:  hook JSON via stdin (session_id, transcript_path, reason).
# Output: nothing relevant — the flag folder is the channel to the next session.
#
# CONTROL_DIR is auto-detected from this script's location (.claude/hooks/ -> repo root).
# Override with CTRL_HOME for isolated tests.
set -uo pipefail

CONTROL_DIR="${CTRL_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PENDING_DIR="$CONTROL_DIR/.pending_session_writes"
SNAP_DIR="$CONTROL_DIR/.session_snapshots"
LOG_FILE="$CONTROL_DIR/.claude/hooks/session_end.log"
mkdir -p "$PENDING_DIR" "$SNAP_DIR" 2>/dev/null

INPUT="$(cat)"
get(){ printf '%s' "$INPUT" | grep -o "\"$1\"[^,}]*" | sed "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/" | head -1; }

SESSION_ID="$(get session_id)"
[ -z "$SESSION_ID" ] && SESSION_ID="unknown-$(date -u +%s)"
TRANSCRIPT="$(get transcript_path)"
REASON="$(get reason)"
END_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Snapshot the transcript NOW, while it still exists (best-effort).
# No-clobber guard: if the PreCompact hook already captured a (richer, pre-compaction) snapshot for this
# session, keep it — don't overwrite it with the now-compacted transcript.
SNAP=""
EXISTING="$SNAP_DIR/$SESSION_ID.jsonl"
if [ -f "$EXISTING" ]; then
  SNAP="$EXISTING"
elif [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  SNAP="$EXISTING"
  cp "$TRANSCRIPT" "$SNAP" 2>/dev/null || SNAP=""
fi

# Per-session flag (NO session number here — the number is assigned at SessionStart, race-free).
cat > "$PENDING_DIR/$SESSION_ID" <<EOF
SESSION_ID=$SESSION_ID
PREV_SESSION_END=$END_TS
REASON=$REASON
TRANSCRIPT=$TRANSCRIPT
SNAPSHOT=$SNAP
EOF

echo "$END_TS session_end: id=$SESSION_ID reason=$REASON snapshot=${SNAP:-NONE}" >> "$LOG_FILE" 2>/dev/null
exit 0
