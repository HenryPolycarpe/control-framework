---
id: RULE-002
title: "Verify, don't claim"
category: rules
status: active
related: [L-001]
sessions: ["001"]
tags: [verification, safety, example]
last_verified: 2026-06-09
---

> EXAMPLE rule.

Never say "it works" / "it runs" / "deployed" without proof: a test pass, a `curl` response, a log line,
a screenshot. Stability beats new features — on risky or hard-to-reverse actions, do a read-only probe
first and ask before the irreversible step.

See [L-001] for a concrete case where skipping verification cost a debugging session.
