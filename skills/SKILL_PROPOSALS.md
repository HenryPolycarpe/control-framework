# Skill Proposal Ledger (the 3x rule)

> **Rule:** a recurring workflow becomes a skill once it has been proposed **3 times**. At every
> consolidation (see `weekly_consolidation.md` step 9c), scan fresh sessions for multi-step,
> cross-project workflows that were re-derived ad hoc. New pattern -> entry with counter 1.
> Recurs -> counter +1 (with date + evidence session). Counter = 3 -> create the skill
> (`skills/<name>.md`), set status to `CREATED: <path>`. Obsolete -> `rejected: <reason>`, never delete.

| # | Proposal | Counter | Evidence (session, date) | Status |
|---|---|---|---|---|
| 1 | _example: "safe deploy to a live server" — pull, anchored patch, syntax check, backup, upload, marker verify_ | 1 | S012 2026-01-01 | open |
