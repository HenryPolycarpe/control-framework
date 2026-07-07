# Agentic Loop: top improvements (living list)

> **Purpose:** the most important, *generalizable* lessons on how the assistant makes its turns and
> its agentic loop more efficient. Injected at **every session start** (hook) and reviewed, sharpened,
> and trimmed at **every consolidation** (every 5 sessions). Not for project-specific facts (those go
> to memories/topics) — only for *working method*.
>
> **Curation rule:** max ~8 entries. Add a new lesson only if it repeatedly cost turns/tokens.
> At consolidation: drop internalized/obsolete points, add new ones.
> Format: **Trigger -> do this** + (evidence/session).

## Current top lessons

1. **Frame-first: before a long chain or a build, confirm the premise + the one fork.** Before >~5
   exploration calls *or* starting a build, state your assumption + the decisive architecture/asset
   fork and falsify/confirm it first. Debugging special case: when "code/disk says X, live says
   0/empty/error", suspect YOUR OWN request first (60s: auth header? path plural/casing? right
   instance/source of truth?), not the server. And deliver an explicit user choice 1:1 — no
   self-authorized "better" substitute. (example entry — replace with your own evidence)

2. **Before first touching a live project -> read its ops card, don't re-discover.** A
   `reference_<project>_ops` memory holds containers, ports, auth, deploy paths, gotchas. Saves
   re-deriving access paths every time.

3. **Delegate broad read-only searches to a subagent instead of walking files inline.** "Where does
   X happen across files/repos/servers?" -> a subagent returns the *conclusion*, keeps your context
   lean, saves turns.

4. **Runtime/state questions: source of truth first.** Don't read a possibly-stale mirror first and
   then verify at the source anyway — go to the source directly.

(Add your own as they earn their place. Entries 1–4 are seed examples from the framework author's
real list — keep what resonates, replace the rest.)

## Candidates / observations (not yet confirmed)
- (park half-confirmed lessons here; promote at consolidation when they recur)
