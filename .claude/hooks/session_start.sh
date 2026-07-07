#!/usr/bin/env bash
# SessionStart hook — processes ALL open session flags from the folder.
# Assigns session numbers HERE (from the real sessions/ state), chronologically, race-free.
# Migrates the legacy single-file flag once. Dedups against already-written recaps.
# Also injects: MEMORY.md (on machines without the native memory symlink), the living
# AGENTIC_LOOP.md work-method lessons, an orphan-memory warning, and an unpushed-commits warning.
#
# Input:  hook JSON via stdin (session_id, source).
# Output: JSON with hookSpecificOutput.additionalContext (injected into the system prompt).
#
# CONTROL_DIR is auto-detected from this script's location (.claude/hooks/ -> repo root).
# Override with CTRL_HOME (isolated tests) or rely on CLAUDE_PROJECT_DIR.
set -uo pipefail

CONTROL_DIR="${CTRL_HOME:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
PENDING_DIR="$CONTROL_DIR/.pending_session_writes"
SNAP_DIR="$CONTROL_DIR/.session_snapshots"
OLD_FLAG="$CONTROL_DIR/.pending_session_write"
SESS_DIR="$CONTROL_DIR/sessions"
LOG_FILE="$CONTROL_DIR/.claude/hooks/session_start.log"
mkdir -p "$PENDING_DIR" "$SESS_DIR" 2>/dev/null

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
CUR_ID="$(get session_id)"
SOURCE="$(get source)"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session_start: id=$CUR_ID source=$SOURCE" >> "$LOG_FILE" 2>/dev/null

# Snapshot pruning (>14 days), best-effort — but NEVER delete snapshots whose session
# still has an open pending flag (a lingering backlog would lose its source).
for s in "$SNAP_DIR"/*.jsonl; do
  [ -f "$s" ] || continue
  sid_s="$(basename "$s" .jsonl)"
  [ -e "$PENDING_DIR/$sid_s" ] && continue
  find "$s" -mtime +14 -delete 2>/dev/null || true
done

# Emit additionalContext JSON-safely (needs python3 on PATH).
emit_context(){
  local cj
  cj=$(printf '%s' "$1" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $cj
  }
}
EOF
}

# ── Memory injection (portable) ──────────────────────────────────────────────
# On machines where Claude Code's native memory loads MEMORY.md through the symlink
# ~/.claude/projects/<hash>/memory -> $CONTROL_DIR/memory, injecting again would duplicate it.
# On web/other machines that symlink is missing -> inject MEMORY.md ourselves so the agent
# wakes up with full auto-memory EVERYWHERE. CTRL_MEMORY=skip/force overrides the detection.
MEM_BLOCK=""
MEM_FILE="$CONTROL_DIR/memory/MEMORY.md"
if [ -f "$MEM_FILE" ] && [ "${CTRL_MEMORY:-auto}" != "skip" ]; then
  native=0
  for d in "$HOME/.claude/projects"/*/memory; do
    [ -L "$d" ] || continue
    [ "$(readlink "$d" 2>/dev/null)" = "$CONTROL_DIR/memory" ] && native=1 && break
  done
  if [ "$native" -eq 0 ] || [ "${CTRL_MEMORY:-auto}" = "force" ]; then
    MEM_BLOCK="## Auto-Memory (MEMORY.md — injected via hook; no native symlink on this machine)

$(cat "$MEM_FILE")

"
  fi
fi

# ── Agentic-loop improvements (always inject, everywhere) ────────────────────
# Living top lessons about HOW to work; curated at every consolidation.
LOOP_BLOCK=""
LOOP_FILE="$CONTROL_DIR/memory/AGENTIC_LOOP.md"
if [ -f "$LOOP_FILE" ]; then
  LOOP_BLOCK="## Agentic Loop — top improvements (injected at session start)

$(cat "$LOOP_FILE")

"
fi

# ── Orphan check (mechanical instead of ritual discipline) ───────────────────
# Memory files without a MEMORY.md pointer are never injected = invisible. Check here
# automatically and inject a warning instead of relying on the skill's step 5b.
ORPHAN_BLOCK=""
orphans=""
if [ -f "$MEM_FILE" ]; then
  for f in "$CONTROL_DIR/memory"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    case "$b" in MEMORY.md|AGENTIC_LOOP.md) continue;; esac
    grep -qF "$b" "$MEM_FILE" 2>/dev/null || orphans="$orphans
- $b"
  done
fi
if [ -n "$orphans" ]; then
  ORPHAN_BLOCK="## ⚠️ ORPHAN MEMORIES (no MEMORY.md pointer -> NEVER injected)
Add an index line to memory/MEMORY.md immediately (or delete the file if obsolete):${orphans}

"
fi

# ── Unpushed-commits warning (makes silent auto-push failures visible) ───────
# session_end.sh pushes in the background and swallows errors; check for leftovers here.
PUSH_BLOCK=""
if git -C "$CONTROL_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  behind=$(git -C "$CONTROL_DIR" log --oneline '@{u}'..HEAD 2>/dev/null | wc -l | tr -d ' ')
  if [ "${behind:-0}" -gt 0 ]; then
    PUSH_BLOCK="## ⚠️ ${behind} unpushed commit(s) in this repo
Auto-push from previous session(s) did not go through (network/auth?). When convenient: \`git push origin HEAD\` — otherwise multi-machine sync goes stale.

"
  fi
fi

# Migrate the legacy single-file flag into the folder, once.
if [ -f "$OLD_FLAG" ]; then
  sid=$(grep -E '^SESSION_ID=' "$OLD_FLAG" | cut -d= -f2- | head -1)
  if [ -n "$sid" ] && [ ! -e "$PENDING_DIR/$sid" ]; then mv "$OLD_FLAG" "$PENDING_DIR/$sid"; else rm -f "$OLD_FLAG"; fi
fi

# Collect open flags: exclude the current session, dedup the already-recapped ones.
# Dedup with fixed-string grep (-F is correct + faster); cover both notations (with/without quotes).
shopt -s nullglob
entries=()
for f in "$PENDING_DIR"/*; do
  [ -f "$f" ] || continue
  sid="$(basename "$f")"
  [ "$sid" = "$CUR_ID" ] && continue
  if grep -rlF "prev_session_id: \"$sid" "$SESS_DIR"/*.md >/dev/null 2>&1 \
     || grep -rlF "prev_session_id: $sid" "$SESS_DIR"/*.md >/dev/null 2>&1; then
    rm -f "$f"; rm -f "$SNAP_DIR/$sid.jsonl" 2>/dev/null; continue
  fi
  endts=$(grep -E '^PREV_SESSION_END=' "$f" | cut -d= -f2- | head -1)
  [ -z "$endts" ] && endts="0000"
  entries+=("$endts|$sid")
done
if [ ${#entries[@]} -eq 0 ]; then
  # No open sessions — still inject memory + agentic loop (+ warnings).
  [ -n "$MEM_BLOCK$LOOP_BLOCK$ORPHAN_BLOCK$PUSH_BLOCK" ] && emit_context "$MEM_BLOCK$LOOP_BLOCK$ORPHAN_BLOCK$PUSH_BLOCK"
  exit 0
fi

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

Open session protocol(s): ${#sorted[@]}. Hooks left one flag per session. FIRST, BEFORE other work — follow skill \`skills/end_of_session.md\`, per entry chronologically. The numbers below reflect the state of NOW — run the collision check from skill step 2 right before writing (a parallel window may have written in the meantime):${LIST}

Per session: read the source (snapshot transcript preferred, else git + artifacts) -> \`sessions/session_NNN.md\` (frontmatter \`prev_session_id\` REQUIRED, max 100 lines, aggressive compaction) -> check auto-memory + \`memory.md\` for updates -> delete flag (\`rm .pending_session_writes/<id>\`) + snapshot (\`rm .session_snapshots/<id>.jsonl\`) -> git commit.${BUCKET_BLOCK}"

emit_context "$MEM_BLOCK$LOOP_BLOCK$ORPHAN_BLOCK$PUSH_BLOCK$CONTEXT"
exit 0
