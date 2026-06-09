---
id: PROC-001
title: "Session Recap + 5-Session Consolidation"
category: processes
status: active
related: [ARCH-001, TOOL-001]
sessions: ["001"]
tags: [process, memory, ritual, example]
last_verified: 2026-06-09
---

> EXAMPLE topic.

## Trigger
Every session start, if `.pending_session_writes/` holds flags (the SessionStart hook says so).

## Recap (every session) — see `skills/end_of_session.md`
1. Read the flag + snapshot transcript.
2. Write `sessions/session_NNN.md` (≤100 lines, with `prev_session_id:` frontmatter — the dedup key).
3. Update auto-memory + `memory.md` if a lasting fact changed.
4. Delete the flag + snapshot.
5. Commit (`git add sessions/ memory/ memory.md`).

## Consolidation (every 5th session) — see `skills/weekly_consolidation.md`
1. Read sessions N-4..N.
2. Distill into `knowledge/*.md` topics (new or extended).
3. Set `related:` both ways.
4. `python3 scripts/build_knowledge_index.py` until 0 broken/dup/missing ([TOOL-001]).
5. Commit `knowledge/ memory.md memory/`.

This is the human-facing description of the loop implemented in [ARCH-001].
