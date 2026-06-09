---
id: D-001
title: "Example decision — the ADR body schema"
category: decisions
status: active
related: [ARCH-001, L-001]
sessions: ["001"]
tags: [example, adr, schema]
last_verified: 2026-06-09
---

> EXAMPLE decision (ADR style). Replace with a real one.

## Context
We needed session knowledge to survive across context windows and accumulate without becoming an
unsearchable pile of transcripts.

## Options
- **A: Single growing memory file** — simple, but bloats and loses structure; no IDs, no cross-refs.
- **B: Hooks + per-session files + periodic consolidation into an indexed knowledge map** — more moving
  parts, but durable, searchable, and self-validating via the index.
- **C: Rely on the model's built-in memory only** — zero infra, but opaque and not git-versioned.

## Decision
Chose **B** ([ARCH-001]). The index build ([TOOL-001]) makes structure enforceable; git makes it durable.

## Consequences
- (+) Knowledge compounds, is greppable, and survives crashes.
- (+) The %5 gate forces distillation.
- (−) More files + a ritual to follow; requires discipline (mitigated by the hooks making it non-optional).

## Status
accepted
