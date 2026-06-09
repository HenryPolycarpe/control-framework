---
id: TOOL-001
title: "Knowledge Index Builder (build_knowledge_index.py)"
category: tools
status: active
related: [PROC-001, ARCH-001]
sessions: ["001"]
tags: [python, index, knowledge, example]
last_verified: 2026-06-09
---

> EXAMPLE topic.

## What
`scripts/build_knowledge_index.py` scans `knowledge/**/*.md`, parses the YAML frontmatter (with a tiny
self-contained parser — stdlib only), and writes `knowledge/INDEX.json`.

## Run
```bash
python3 scripts/build_knowledge_index.py
```
Output: `N topics indexed, X orphans, Y broken refs, Z duplicates, W missing-frontmatter`.

## Exit codes
- `0` — clean (or knowledge dir empty)
- `1` — problems detected (broken_refs / duplicates / missing_frontmatter / category mismatch)

INDEX.json is **always** written, regardless of exit code.

## What it validates
- Every `.md` has frontmatter with an `id`.
- The `id` prefix matches the directory (`L-*` lives in `learnings/`, etc.).
- `frontmatter category` matches the directory.
- Every `related:` id points to an existing topic.
- No duplicate ids.

## Aggregations it produces
`by_category`, `by_session`, `by_tag`, `orphans` (topics with no `related:`), plus the problem lists.
Query it instead of reading it whole:
```bash
grep -iE 'keyword' knowledge/INDEX.json
```

## Suggested cron (daily)
```cron
17 3 * * * cd /path/to/your/control && /usr/bin/python3 scripts/build_knowledge_index.py >> .claude/hooks/build_index.log 2>&1
```
