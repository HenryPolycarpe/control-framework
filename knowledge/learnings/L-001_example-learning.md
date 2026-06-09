---
id: L-001
title: "Example learning — the L-NNN body schema"
category: learnings
status: active
related: [RULE-002, D-001]
sessions: ["001"]
tags: [example, schema]
last_verified: 2026-06-09
---

> EXAMPLE learning. This shows the required body sections. Replace with a real fix.

## Error
A change was reported as "working" and committed without running it. The next session found it broke a
downstream consumer — a whole debugging session was spent rediscovering the regression.

## Root Cause
No verification step. The claim of success was based on reading the diff, not on observing behavior.

## Fix
Run the thing. Add the proof (test output / curl / log line) to the session recap. Codified as [RULE-002].

## Lesson
Whenever a change touches runtime behavior -> observe it run before claiming success. A clean diff is
not evidence.

## Fallout
Promoted to a standing rule ([RULE-002]) and informed decision [D-001] (CI gate).
