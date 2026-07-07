#!/usr/bin/env bash
# SessionEnd hook — drops one per-session flag into a folder + snapshots the transcript immediately.
# Fixes: single-file-flag race (overwrite on fast back-to-back sessions) + transcript-gone-when-consumed.
# Also: best-effort auto-push of committed-but-unpushed commits to origin (multi-machine sync).
#
# Input:  hook JSON via stdin (session_id, transcript_path, reason).
# Output: nothing relevant — the flag folder is the channel to the next session.
#
# CONTROL_DIR is auto-detected from this script's location (.claude/hooks/ -> repo root).
# Override with CTRL_HOME (isolated tests) or rely on CLAUDE_PROJECT_DIR.
set -uo pipefail

CONTROL_DIR="${CTRL_HOME:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
PENDING_DIR="$CONTROL_DIR/.pending_session_writes"
SNAP_DIR="$CONTROL_DIR/.session_snapshots"
LOG_FILE="$CONTROL_DIR/.claude/hooks/session_end.log"
mkdir -p "$PENDING_DIR" "$SNAP_DIR" 2>/dev/null

INPUT="$(cat)"
# Robust: real JSON parsing via python3 (handles escapes/null/format variants the old grep/sed
# extraction silently lost — ~6% snapshot=NONE in the log). Fallback: the old method.
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
REASON="$(get reason)"
END_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Snapshot the transcript NOW, while it still exists (best-effort, but LOG errors instead of swallowing).
# No-clobber guard: if the PreCompact hook already captured a (richer, pre-compaction) snapshot for this
# session, keep it — don't overwrite it with the now-compacted transcript.
SNAP=""
EXISTING="$SNAP_DIR/$SESSION_ID.jsonl"
if [ -f "$EXISTING" ]; then
  SNAP="$EXISTING"
elif [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  SNAP="$EXISTING"
  if ! cp "$TRANSCRIPT" "$SNAP" 2>>"$LOG_FILE"; then
    echo "$END_TS ERROR snapshot-cp failed: $TRANSCRIPT" >> "$LOG_FILE" 2>/dev/null
    SNAP=""
  fi
else
  echo "$END_TS WARN no transcript to snapshot (transcript_path='${TRANSCRIPT:-}')" >> "$LOG_FILE" 2>/dev/null
fi

# Per-session flag (NO session number here — the number is assigned at SessionStart, race-free).
# Atomic: tempfile first (dotfile -> doesn't match the glob in session_start.sh), then rename.
TMP_FLAG="$PENDING_DIR/.$SESSION_ID.tmp.$$"
cat > "$TMP_FLAG" <<EOF
SESSION_ID=$SESSION_ID
PREV_SESSION_END=$END_TS
REASON=$REASON
TRANSCRIPT=$TRANSCRIPT
SNAPSHOT=$SNAP
EOF
mv -f "$TMP_FLAG" "$PENDING_DIR/$SESSION_ID"

echo "$END_TS session_end: id=$SESSION_ID reason=$REASON snapshot=${SNAP:-NONE}" >> "$LOG_FILE" 2>/dev/null

# Auto-sync (this machine = writer): best-effort push of committed-but-unpushed commits to origin.
# Other machines pull independently (e.g. cron with git pull --ff-only) -> one source of truth on the
# remote, no machine-to-machine SSH needed. Strictly non-blocking + non-fatal: runs in the background,
# with a timeout, never fails the hook (network/offline/auth issues are fine). Failures additionally
# surface as a warning injected by the SessionStart hook (unpushed-commits check there).
if git -C "$CONTROL_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  if [ -n "$(git -C "$CONTROL_DIR" log --oneline '@{u}'..HEAD 2>/dev/null)" ]; then
    (
      if command -v timeout >/dev/null 2>&1; then PUSH="timeout 30 git"; else PUSH="git"; fi
      if $PUSH -C "$CONTROL_DIR" push --quiet origin HEAD 2>>"$LOG_FILE"; then
        echo "$END_TS auto-push: ok -> origin" >> "$LOG_FILE" 2>/dev/null
      else
        echo "$END_TS auto-push: FAILED (next session catches up)" >> "$LOG_FILE" 2>/dev/null
      fi
    ) &
  fi
fi

exit 0
