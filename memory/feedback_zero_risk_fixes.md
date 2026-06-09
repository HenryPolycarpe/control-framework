---
name: Zero-risk fixes → just do it
description: Implement no-risk / trivial improvements directly, without asking for confirmation
metadata:
  type: feedback
---

> EXAMPLE memory of type `feedback`.

When a fix is genuinely no-risk or trivial (CSS, copy, defensive guards, one-line bugfix), implement and
ship it directly instead of asking. For architectural changes, do a quick re-evaluation that all problems
are really solved, then go.

**Why:** speed on trivial fixes; reserve confirmation loops for risky or irreversible actions.

**How to apply:** trivial -> do it + mention it in the summary. Risky/irreversible -> probe read-only, ask first.
