# Skill: Session Reconstruction (working off a recap backlog)

**When:** the SessionStart hook reports **more than ~3 open flags** in `.pending_session_writes/`,
or sessions have to be reconstructed forensically (crashed window, another machine, empty snapshot).

**Goal:** clear the whole backlog in one pass — in parallel, verified, without losing a source.

> This skill exists because the ledger rule worked: "reconstruct a lost session" was proposed at
> three separate consolidations before it earned its own playbook (see `SKILL_PROPOSALS.md`).

---

## 1. Inventory — one bash pass, not a ritual per flag

```bash
ls sessions/ | grep -oE '[0-9]+' | sort -n | tail -1     # real highest number (never from memory!)
HASH=~/.claude/projects/*                                # your project dir (transcripts live here)
for f in .pending_session_writes/*; do
  sid=$(basename "$f"); s=".session_snapshots/$sid.jsonl"
  printf '%s snap=%s flag=%s\n' "$sid" \
    "$( [ -f "$s" ] && wc -c < "$s" || echo MISSING )" "$(wc -c < "$f")"
done
```

**Size heuristic:** a flag with an empty `SNAPSHOT=` line (~240 bytes) is an *empty session* — an
editor window that opened and closed, often several per minute. A flag carrying a snapshot path
(~350 bytes) has a real source. Sort by this before spending anything.

## 2. Triage into three classes

- **Empty** (no snapshot, no transcript) → minimal recap in a scripted loop: `prev_session_id`
  frontmatter + one honest line ("empty session, no transcript, ended <ts>"). Cheap, truthful,
  and the flag becomes removable.
- **Source present** → fan out to subagents, 3–4 sessions per agent, chronological batches.
- **0-byte snapshot but work suspected** → git fallback (`git log --since` here + in the project
  repos + artifacts). Attribute a commit to a session only by grepping the candidate transcript,
  never by timestamp alone.

## 3. Subagent briefing (what makes the difference)

- Hand over the **number mapping** (NNN ← session_id) explicitly; numbers come from the
  SessionStart hook, collision-checked against the real `sessions/` state right before writing.
- **Never** read a JSONL transcript whole — extract user texts (full) + assistant text blocks
  (~300 chars), see `end_of_session.md` step 3.
- Format: the `end_of_session.md` template, ≤100 lines, `prev_session_id` frontmatter mandatory.
- Forbidden for agents: deleting flags/snapshots, committing, editing memory — the orchestrator
  does that centrally, after verification.
- Return value: short summary + tagged candidates `LEARNING:` / `DECISION:` / `SKILL-CANDIDATE:` /
  `PROJECT-UPDATE:` — that is the input for the consolidation that follows.
- **Plan for aborts:** long fan-outs lose agents to API errors. Before re-dispatching, check which
  files already exist and re-brief only the remainder.

## 4. Verify before cleaning up

```bash
for n in $(seq -w A B); do f=sessions/session_$n.md
  [ -f "$f" ] || echo "MISSING $f"
  grep -q prev_session_id "$f" 2>/dev/null || echo "NO-FRONTMATTER $f"
done
grep -h 'prev_session_id:' sessions/session_*.md | sort | uniq -d    # duplicate check
```

## 5. Consolidate + clean up — in this order

1. Due buckets in ONE collective pass (`weekly_consolidation.md`) from the agents' returns.
2. `python3 scripts/build_knowledge_index.py` green.
3. **Only then** delete flags + snapshots (`rm .pending_session_writes/<id> .session_snapshots/<id>.jsonl`).
4. Commit (`sessions/ knowledge/ memory/ memory.md skills/`) — explicit paths, never `git add -A`.

## Anti-patterns

- Writing dozens of recaps inline yourself (context explosion) instead of fanning out.
- Deleting flags before the recaps exist and the index is green — source gone, backlog unrecoverable.
- Taking the hook's numbers without a collision check against the real `sessions/` state.
- Spending expensive agents on empty flags — run the size heuristic first.
