# Skill Proposal Ledger (the 3× rule)

> **Rule:** a recurring workflow becomes a skill once it has shown up in **3 separate
> consolidations**. At every consolidation (`weekly_consolidation.md` step 9c) scan the fresh
> sessions for multi-step, cross-project workflows that were re-derived ad hoc.
> New pattern → entry with counter 1. Recurs → counter +1 (date + evidence). **Counter = 3 → write
> the skill**, set status `CREATED: <path>`. No longer relevant → `rejected: <reason>`.
> Never delete a row — the history is what makes the counter trustworthy.
>
> The counter counts *independent consolidations*, not single sessions inside the same bucket.
> That is the point: it separates "was annoying once" from "recurs structurally".

## Format per entry
`### <skill-name>` · what/steps · evidence sessions · counter log (date → evidence) · status

---

### session-reconstruction
**What:** work off a recap backlog forensically: read the flags → stream snapshot/transcript (never
read a >1 MB JSONL whole) → git fallback for missing sources → triage by size heuristic → parallel
subagents → verify → only then clean up.
**Evidence:** 3 marathons — 3 parallel reconstruction agents; 31 recaps (21 agents + git fallback for
10 snapshot-less sessions); 40 recaps (6 fan-out agents, 17 sourceless empty flags).
**Counter: 3** — 2026-07-05 · 2026-07-12 · 2026-07-19
**Status:** `CREATED: skills/session_reconstruction.md` (2026-07-19) — this is the rule working:
three independent occurrences, then a playbook instead of a fourth improvisation.

### safe-deploy-to-live
**What:** _(example row — replace with your own)_ pull first, anchored patch instead of blind
overwrite, syntax check, backup, upload, verify by marker.
**Evidence:** S012.
**Counter: 1** — 2026-01-01
**Status:** open
