---
id: ARCH-001
title: "Compound Memory System"
category: architecture
status: active
related: [PROC-001, TOOL-001, RULE-001]
sessions: ["001"]
tags: [memory, hooks, architecture, example]
last_verified: 2026-06-09
---

> EXAMPLE topic. Delete or replace once you have real architecture to document.

## Overview
Three layers that turn ephemeral chat sessions into durable, compounding knowledge:

1. **Auto-memory** (`memory/`) — small atomic facts, each one file with frontmatter. The index
   `memory/MEMORY.md` is injected into every session at start (via the assistant's memory feature),
   so the assistant always boots with the rough map.
2. **`memory.md`** — a single consolidated human-readable state file (current projects, open threads).
3. **`sessions/`** — one compacted protocol per session (`session_NNN.md`).

On top sits the **knowledge map** (`knowledge/`, see [PROC-001]): structured, ID'd topics that the
5-session consolidation distills out of the raw sessions.

## Data flow
```
SessionEnd hook  ──> .pending_session_writes/<id>   (flag)
                 └─> .session_snapshots/<id>.jsonl   (transcript snapshot)
                              │
SessionStart hook ──reads flags──> injects "write the recap first" into the system prompt
                              │
assistant follows end_of_session ──> sessions/session_NNN.md  + memory updates
                              │
every 5th session ──> weekly_consolidation ──> knowledge/*.md ──> INDEX.json (TOOL-001)
```

## Why it compounds
The hooks make the ritual non-optional: you literally cannot start fresh work without first being told
about the unwritten recap. Snapshots mean a crashed/closed session is still recoverable. Git versioning
means nothing is silently lost. The %5 gate forces periodic distillation so `sessions/` never becomes an
unsearchable pile.

## Files
- `.claude/hooks/session_end.sh`, `.claude/hooks/session_start.sh`
- `skills/end_of_session.md`, `skills/weekly_consolidation.md`
- `scripts/build_knowledge_index.py` (see [TOOL-001])
