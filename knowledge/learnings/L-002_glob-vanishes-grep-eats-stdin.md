---
id: L-002
title: "An empty glob makes grep read STDIN — and a hook hangs"
category: learnings
status: active
related: [PROC-001, RULE-002]
sessions: ["002"]
tags: [bash, hooks, glob, nullglob, stdin, real]
last_verified: 2026-07-25
---

> REAL learning from this framework — kept as the reference example of the L-NNN schema, because it
> is exactly the class of bug the machine is built to remember.

## Error
The SessionStart hook stopped listing pending sessions, and under some shells it hung outright — which
blocks the start of Claude Code itself. It only happened on instances whose `sessions/` folder held no
`*.md` file yet: a brand-new install, or one where the example session had been deleted as the README
told the user to do.

## Root Cause
The dedup check ran `grep -rlF "prev_session_id: $sid" "$SESS_DIR"/*.md`. With `shopt -s nullglob`
active (set a few lines above, for the flag loop), an empty folder makes the glob expand to *nothing*.
`grep` then has a pattern but no file operand — so by POSIX it reads **stdin**. The hook's stdin is the
JSON event channel; depending on whether the caller keeps it open, grep either consumes it or blocks
forever. Neither is visible in a log: the hook simply produced no output.

## Fix
Hand grep the **directory** and let `-r` walk it — a directory that exists always terminates:
```bash
grep -rlF "prev_session_id: $sid" "$SESS_DIR" >/dev/null 2>&1
```
Covered by `scripts/selftest.sh` (case: pending flag + empty `sessions/` must still assign a number).

## Lesson
Whenever a glob feeds a command that falls back to stdin (`grep`, `cat`, `awk`, `sed`, `sort`), pass a
directory or guard the expansion — an empty match is not "no work", it is a *different command*. And
any check that can hang belongs in a self-test, because a hang produces no error message to grep for.

## Fallout
Found by writing the self-test, not by reading the code ([RULE-002]: a green read-through is not
evidence). Same bug existed in the instance this framework was extracted from — latent there only
because that `sessions/` folder is never empty. See [PROC-001] for the ritual the hook drives.
