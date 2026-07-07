# Skill: End of Session Ritual

**When:** At session start, when the SessionStart hook reports open flags in
`.pending_session_writes/` (the SessionEnd hook left one per finished session).

**Goal:** No session is lost. Compound memory grows — without duplicates, without context loss.

---

## Steps (run in this order, one pass per open flag, chronologically)

### 1. Read the flag and get the session id
```bash
cat .pending_session_writes/<session-id>
# Format: SESSION_ID=<claude-code-session-uuid>
#         PREV_SESSION_END=<iso-timestamp>
#         REASON=<why the session ended>
#         TRANSCRIPT=<path to the live transcript>
#         SNAPSHOT=<path to the saved snapshot, preferred source>
```
The session **number** comes from the list injected by the SessionStart hook (assigned from the
real `sessions/` state).

### 2. Collision & dedup check (required — multi-window protection)
The injected number reflects the state at session start; a parallel window may have written in the
meantime. Right before writing:
```bash
ls sessions/ | tail -3                                    # session_NNN.md already exists? -> fall back to highest+1
grep -rl "prev_session_id: <SESSION_ID>" sessions/*.md    # already recapped? -> just delete flag+snapshot, done
```

### 3. Reconstruct the previous session
- Prefer the snapshot transcript (`.session_snapshots/<id>.jsonl`) — read it for what actually happened.
- Else fall back to: `git log --since "<PREV_SESSION_END>"` in this repo and any related repos,
  plus any artifacts created since (reports, generated files).

### 4. Write `sessions/session_NNN.md`
Max 100 lines. Aggressive compaction. Template:

```markdown
---
session: NNN
date: YYYY-MM-DD
prev_session_id: "<the session uuid from the flag>"   # REQUIRED — dedup key for the hook
---

# Session NNN — YYYY-MM-DD

## What happened
- (3-8 bullets of the most important work — what was actually changed, not what was attempted)

## Decisions
- (decision + rationale + trade-off in 1-2 lines)

## Lessons learned
- (only if non-trivial — "when X, then Y else Z")

## Open threads
- (what the next session must pick up, who is waiting on what)

## Artifacts
- (commit hashes, created files, changed files — short)
```

> The `prev_session_id:` frontmatter line is **load-bearing**: the SessionStart hook greps for it to
> know a flag has been consumed and to delete it. Omit it and the same session is offered forever.

### 5. Check auto-memory for updates
For each file in `memory/`:
- Is the core statement still true? -> if not: correct or delete it.
- New feedback/project facts not yet captured? -> create a new file, add a line to `memory/MEMORY.md`.
- Duplicates? -> merge, remove the old file.

**Rules:**
- New memory only for lasting insight — not day-to-day session chatter.
- Each memory: ~40 lines max, clear frontmatter (`name`, `description`, `metadata.type`).
- `MEMORY.md` index: one line per memory, ~150 chars max.

### 5b. Orphan check (required — prevents invisible memories)
Any `memory/` file without a pointer in `MEMORY.md` is NEVER injected at session start -> it is
effectively invisible and gets expensively rediscovered by hand. So check on EVERY recap:
```bash
for f in memory/*.md; do b=$(basename "$f"); [ "$b" = MEMORY.md ] || [ "$b" = AGENTIC_LOOP.md ] && continue; grep -qF "$b" memory/MEMORY.md || echo "ORPHAN (no index pointer): $b"; done
```
Add an index line to `MEMORY.md` for every ORPHAN immediately (or delete the file if obsolete).
Should be empty at the end. (The SessionStart hook also checks this mechanically and injects a
warning — this step is the fix, the hook is the safety net.)

### 6. Update `memory.md` (if needed)
- Status changes in "Current state" — **bump the section's date header too**
- New lessons under "Lessons learned" only if truly universal
- New open items under "Open threads"

### 7. Trigger consolidation (when session number % 5 == 0)
-> Run skill `weekly_consolidation.md` (HARD GATE — do not defer; deferred buckets get more
expensive every day).

### 8. Remove the flag + snapshot
```bash
rm .pending_session_writes/<session-id>
rm -f .session_snapshots/<session-id>.jsonl
```

### 9. Git commit
```bash
git add sessions/ memory/ memory.md
git commit -m "Session NNN recap — <short summary>"
```

---

## Anti-patterns
- ❌ A 300-line session file ("I did everything I did")
- ❌ Listing tool calls ("Read, Edit, Bash, Read, Edit...")
- ❌ Preserving success messages ("works as expected")
- ❌ A new auto-memory for every small session insight
- ❌ Deleting old memory without checking the content was carried into the summary
- ❌ A recap without `prev_session_id` frontmatter (blinds the hook's dedup -> flag lingers forever)
