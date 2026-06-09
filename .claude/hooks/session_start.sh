#!/usr/bin/env bash
# SessionStart hook — processes ALL open session flags from the folder.
# Assigns session numbers HERE (from the real sessions/ state), chronologically, race-free.
# Migrates the legacy single-file flag once. Dedups against already-written recaps.
#
# Input:  hook JSON via stdin (session_id, source).
# Output: JSON with hookSpecificOutput.additionalContext (injected into the system prompt).
#
# CONTROL_DIR is auto-detected from this script's location (.claude/hooks/ -> repo root).
# Override with CTRL_HOME for isolated tests.
set -uo pipefail

CONTROL_DIR="${CTRL_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PENDING_DIR="$CONTROL_DIR/.pending_session_writes"
SNAP_DIR="$CONTROL_DIR/.session_snapshots"
OLD_FLAG="$CONTROL_DIR/.pending_session_write"
SESS_DIR="$CONTROL_DIR/sessions"
LOG_FILE="$CONTROL_DIR/.claude/hooks/session_start.log"
mkdir -p "$PENDING_DIR" "$SESS_DIR" 2>/dev/null

INPUT="$(cat)"
get(){ printf '%s' "$INPUT" | grep -o "\"$1\"[^,}]*" | sed "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/" | head -1; }
CUR_ID="$(get session_id)"
SOURCE="$(get source)"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session_start: id=$CUR_ID source=$SOURCE" >> "$LOG_FILE" 2>/dev/null

# Snapshot pruning (>14 days), best-effort.
find "$SNAP_DIR" -type f -mtime +14 -delete 2>/dev/null || true

# Migrate the legacy single-file flag into the folder, once.
if [ -f "$OLD_FLAG" ]; then
  sid=$(grep -E '^SESSION_ID=' "$OLD_FLAG" | cut -d= -f2- | head -1)
  if [ -n "$sid" ] && [ ! -e "$PENDING_DIR/$sid" ]; then mv "$OLD_FLAG" "$PENDING_DIR/$sid"; else rm -f "$OLD_FLAG"; fi
fi

# Collect open flags: exclude the current session, dedup the already-recapped ones.
shopt -s nullglob
entries=()
for f in "$PENDING_DIR"/*; do
  [ -f "$f" ] || continue
  sid="$(basename "$f")"
  [ "$sid" = "$CUR_ID" ] && continue
  if grep -rlE "prev_session_id: *\"?$sid" "$SESS_DIR"/*.md >/dev/null 2>&1; then
    rm -f "$f"; rm -f "$SNAP_DIR/$sid.jsonl" 2>/dev/null; continue
  fi
  endts=$(grep -E '^PREV_SESSION_END=' "$f" | cut -d= -f2- | head -1)
  [ -z "$endts" ] && endts="0000"
  entries+=("$endts|$sid")
done
[ ${#entries[@]} -eq 0 ] && exit 0

# Sort chronologically (by end time).
IFS=$'\n' sorted=($(printf '%s\n' "${entries[@]}" | sort)); unset IFS

# Find the highest existing session number.
LAST_NUM=$(ls -1 "$SESS_DIR"/ 2>/dev/null | grep -E '^session_[0-9]+\.md$' | sed 's/session_0*\([0-9]*\)\.md/\1/' | sort -n | tail -1)
LAST_NUM=${LAST_NUM:-0}

# Build the list + detect the %5 gate.
LIST=""; GATE_NUM=""; n=$LAST_NUM
for e in "${sorted[@]}"; do
  endts="${e%%|*}"; sid="${e#*|}"
  f="$PENDING_DIR/$sid"
  n=$((n+1)); num=$(printf "%03d" "$n")
  snap=$(grep -E '^SNAPSHOT=' "$f" | cut -d= -f2- | head -1)
  tr=$(grep -E '^TRANSCRIPT=' "$f" | cut -d= -f2- | head -1)
  src="${snap:-${tr:-(no transcript — reconstruct from git log + artifacts)}}"
  LIST="$LIST
- \`session_${num}.md\` <- session id \`$sid\` (ended $endts); source: $src; flag: \`.pending_session_writes/$sid\`"
  if (( 10#$num % 5 == 0 )); then GATE_NUM="$num"; fi
done

BUCKET_BLOCK=""
if [ -n "$GATE_NUM" ]; then
  BUCKET_BLOCK="

## HARD GATE — consolidation due (session ${GATE_NUM})
Session number ${GATE_NUM} is divisible by 5 -> consolidation is DUE. Run skill \`skills/weekly_consolidation.md\` BEFORE any other work — until \`python3 scripts/build_knowledge_index.py\` runs with no broken_refs/duplicates/missing-frontmatter."
fi

CONTEXT="## Pending Session Write Ritual (Compound Memory)

Open session protocol(s): ${#sorted[@]}. Hooks left one flag per session. FIRST, BEFORE other work — follow skill \`skills/end_of_session.md\`, per entry chronologically:${LIST}

Per session: read the source (snapshot transcript preferred, else git + artifacts) -> \`sessions/session_NNN.md\` (max 100 lines, aggressive compaction) -> check Auto-Memory + \`memory.md\` for updates -> delete flag (\`rm .pending_session_writes/<id>\`) + snapshot (\`rm .session_snapshots/<id>.jsonl\`) -> git commit.${BUCKET_BLOCK}"

CONTEXT_JSON=$(printf '%s' "$CONTEXT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $CONTEXT_JSON
  }
}
EOF
exit 0
