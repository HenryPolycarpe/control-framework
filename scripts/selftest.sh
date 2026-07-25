#!/usr/bin/env bash
# selftest.sh — proves the compound-memory machine actually works on THIS machine.
#
# Runs the real hooks against a disposable sandbox (a temp CTRL_HOME), never touching your
# sessions/, memory/ or flags. Used by install.sh as the final step and by CI on every push.
#
#   bash scripts/selftest.sh          # human output
#   bash scripts/selftest.sh --quiet  # only failures + summary (CI)
#
# Exit 0 = every check passed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
PASS=0; FAIL=0
say(){ [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok(){   PASS=$((PASS+1)); say "  ok   $1"; }
bad(){  FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/control-selftest.XXXXXX")"
cleanup(){ rm -rf "$SANDBOX"; }
trap cleanup EXIT

say "Control self-test"
say "  repo:    $ROOT"
say "  sandbox: $SANDBOX"
say

# ── 0. prerequisites ────────────────────────────────────────────────────────
command -v bash    >/dev/null 2>&1 && ok "bash present" || bad "bash missing"
if command -v python3 >/dev/null 2>&1; then
  ok "python3 present ($(python3 -c 'import sys;print(".".join(map(str,sys.version_info[:3])))'))"
else
  bad "python3 missing" "the hooks parse their JSON input with python3 — install it (stdlib only, no pip)"
fi

# ── 1. every hook is syntactically valid ────────────────────────────────────
for h in "$ROOT"/.claude/hooks/*.sh; do
  if bash -n "$h" 2>/dev/null; then ok "syntax $(basename "$h")"; else bad "syntax $(basename "$h")"; fi
done
if python3 -c "import json,sys; json.load(open('$ROOT/.claude/settings.json'))" 2>/dev/null; then
  ok "settings.json is valid JSON"
else
  bad "settings.json is not valid JSON"
fi

# ── 2. build the sandbox instance ───────────────────────────────────────────
mkdir -p "$SANDBOX/.claude/hooks" "$SANDBOX/sessions" "$SANDBOX/memory"
cp "$ROOT"/.claude/hooks/*.sh "$SANDBOX/.claude/hooks/"
printf '# MEMORY index\n- [Example](example.md) — hook\n' > "$SANDBOX/memory/MEMORY.md"
printf '# Agentic loop\n- example lesson\n' > "$SANDBOX/memory/AGENTIC_LOOP.md"
printf 'transcript line 1\ntranscript line 2\n' > "$SANDBOX/fake_transcript.jsonl"
export CTRL_HOME="$SANDBOX"
export CTRL_MEMORY=skip   # don't depend on the host's ~/.claude symlink layout

hook(){ printf '%s' "$2" | bash "$SANDBOX/.claude/hooks/$1"; }

# ── 3. SessionEnd: flag + snapshot ──────────────────────────────────────────
hook session_end.sh '{"session_id":"selftest-1","transcript_path":"'"$SANDBOX"'/fake_transcript.jsonl","reason":"clear"}' >/dev/null 2>&1
[ -f "$SANDBOX/.pending_session_writes/selftest-1" ] \
  && ok "SessionEnd wrote the pending flag" \
  || bad "SessionEnd wrote no flag" "expected $SANDBOX/.pending_session_writes/selftest-1"
[ -s "$SANDBOX/.session_snapshots/selftest-1.jsonl" ] \
  && ok "SessionEnd snapshotted the transcript" \
  || bad "SessionEnd did not snapshot the transcript"

# ── 4. SessionStart: valid JSON + recap instruction + session number ─────────
OUT="$(hook session_start.sh '{"session_id":"selftest-2","source":"startup"}' 2>/dev/null)"
CTX="$(printf '%s' "$OUT" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
sys.stdout.write(d.get("hookSpecificOutput",{}).get("additionalContext",""))' 2>/dev/null)"
if [ -n "$CTX" ]; then ok "SessionStart emitted valid hook JSON"; else bad "SessionStart emitted no/invalid JSON" "$(printf '%s' "$OUT" | head -3)"; fi
case "$CTX" in *"session_001.md"*) ok "session number assigned from real sessions/ state (001)";;
                *) bad "no session number in the injected context";; esac
case "$CTX" in *"selftest-1"*) ok "the pending session is named in the recap instruction";;
                *) bad "pending session id missing from the context";; esac

# ── 5. the %5 hard gate ─────────────────────────────────────────────────────
for n in 001 002 003 004; do printf -- '---\nprev_session_id: "old-%s"\n---\n' "$n" > "$SANDBOX/sessions/session_$n.md"; done
CTX5="$(hook session_start.sh '{"session_id":"selftest-3","source":"startup"}' 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)"
case "$CTX5" in *"HARD GATE"*) ok "consolidation hard gate fires on session 005";;
                 *) bad "hard gate did NOT fire on session 005";; esac

# ── 6. dedup: a written recap consumes its flag ─────────────────────────────
printf -- '---\nprev_session_id: "selftest-1"\n---\n# recap\n' > "$SANDBOX/sessions/session_005.md"
hook session_start.sh '{"session_id":"selftest-4","source":"startup"}' >/dev/null 2>&1
[ -e "$SANDBOX/.pending_session_writes/selftest-1" ] \
  && bad "flag survived although a recap with its prev_session_id exists" "dedup is broken -> the same session is offered forever" \
  || ok "dedup removed the consumed flag"

# ── 7. orphan-memory warning ────────────────────────────────────────────────
printf 'orphan\n' > "$SANDBOX/memory/not_in_index.md"
CTXO="$(hook session_start.sh '{"session_id":"selftest-5","source":"startup"}' 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)"
case "$CTXO" in *"not_in_index.md"*) ok "orphan-memory warning works";;
                 *) bad "orphan memory was not reported";; esac

# ── 8. git-add guard ────────────────────────────────────────────────────────
DENY="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git add -A"}}' | bash "$SANDBOX/.claude/hooks/block_git_add_all.sh" 2>/dev/null)"
case "$DENY" in *'"deny"'*) ok "block_git_add_all denies 'git add -A'";; *) bad "'git add -A' was NOT blocked";; esac
ALLOW="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git add sessions/session_001.md"}}' | bash "$SANDBOX/.claude/hooks/block_git_add_all.sh" 2>/dev/null)"
case "$ALLOW" in *'"deny"'*) bad "explicit 'git add <path>' was wrongly blocked";; *) ok "explicit 'git add <path>' passes";; esac

# ── 9. no auto-push to the upstream template ────────────────────────────────
if grep -q 'control-framework' "$SANDBOX/.claude/hooks/session_end.sh"; then
  ok "session_end refuses to auto-push to the template remote"
else
  bad "session_end has no template-remote guard" "a clone would try to push your private memory to the framework repo"
fi

# ── 10. knowledge index builds clean ────────────────────────────────────────
if [ -f "$ROOT/scripts/build_knowledge_index.py" ]; then
  IDXOUT="$(cd "$ROOT" && python3 scripts/build_knowledge_index.py 2>&1)"; IDXRC=$?
  if [ $IDXRC -eq 0 ]; then ok "knowledge index builds clean (${IDXOUT%%$'\n'*})"
  else bad "knowledge index build failed (exit $IDXRC)" "$IDXOUT"; fi
fi

say
if [ "$FAIL" -eq 0 ]; then
  printf 'self-test: %d/%d checks passed — the compound-memory loop works on this machine.\n' "$PASS" "$PASS"
  exit 0
fi
printf 'self-test: %d passed, %d FAILED.\n' "$PASS" "$FAIL"
exit 1
