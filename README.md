# Control — a compound-memory framework for Claude Code

**Turn Claude Code into a persistent, self-documenting personal engineer that gets smarter every
session instead of forgetting everything when the context window closes.**

Control is the operating system for a long-lived AI assistant. It's a small, dependency-free layer
(bash hooks + Python stdlib + markdown conventions) that wraps [Claude Code](https://claude.com/claude-code)
so that:

- every session is **captured** automatically when it ends,
- the next session is **forced to write a recap** before doing anything else,
- recaps **consolidate** into a structured, validated knowledge base every few sessions,
- the assistant **boots with a map** of everything it has learned.

Nothing here is project-specific. It's the scaffolding one person used to run an assistant ("Control")
across many projects and a production server — extracted, anonymized, and made adoptable. Clone it, run
the installer, and you have your own.

> This repo is a **template**, not a running instance. Files contain `{{PLACEHOLDERS}}` and `EXAMPLE`
> topics. `install.sh` fills the placeholders; you delete the examples as you add real content.

---

## Why this exists

Claude Code is stateless across sessions. Each new conversation starts from zero — it re-reads the code,
re-derives context, repeats yesterday's mistakes. For one-off tasks that's fine. For a **standing
assistant that owns your stack**, it's the central problem.

The naive fix — "just put everything in CLAUDE.md" — collapses: the file bloats, loses structure, and
the model can't tell current truth from stale notes. Control solves it with **compound memory**: a small
amount of state that is captured automatically, distilled periodically, and ranked by a clear hierarchy
so conflicts resolve deterministically.

The result compounds. Session 50 starts knowing what sessions 1–49 learned, in a form that's greppable,
cross-referenced, and self-validating.

---

## How it compares

The Claude-Code-memory niche is crowded. Most tools either install a black-box plugin backed by a vector
database, or bolt on a general-purpose agent-memory framework. Control sits at the opposite corner:
**plain-markdown, git-native, zero-dependency, and you own every file.** Star counts as of 2026-06-09.

| Project | ⭐ | Storage | Deps | Differentiator vs. Control |
|---|--:|---|---|---|
| [everything-claude-code](https://github.com/affaan-m/everything-claude-code) | 211k | flat files | medium | Omnibus harness (64 agents, 261 skills); heavy, opinionated about your whole workflow |
| [MCP memory server](https://github.com/modelcontextprotocol/servers/tree/main/src/memory) | 87k | JSONL graph | TS/Docker | Official knowledge-graph via MCP tool calls; no hooks, no ritual |
| [claude-mem](https://github.com/thedotmack/claude-mem) | 81k | SQLite + ChromaDB | heavy | AI-compressed capture + vector retrieval; opaque, needs ChromaDB/Bun/uv |
| [mem0](https://github.com/mem0ai/mem0) | 58k | vector + graph | heavy | General memory layer for any agent; not Claude-Code-specific |
| [graphiti](https://github.com/getzep/graphiti) | 27k | Neo4j graph | heavy | Temporal knowledge graph; infra-heavy |
| [letta (MemGPT)](https://github.com/letta-ai/letta) | 23k | Postgres + vector | heavy | Stateful tiered-memory agents; a runtime, not a scaffold |
| [basic-memory](https://github.com/basicmachines-co/basic-memory) | 3.2k | plain markdown | Python+MCP | MCP-native markdown, cross-client; no enforced rituals/validation |
| [claude-memory-compiler](https://github.com/coleam00/claude-memory-compiler) | 1.1k | markdown articles | Python+SDK | SDK auto-extracts knowledge; no schema/index validation |
| [claude-memory-kit](https://github.com/awrshift/claude-memory-kit) | 21 | plain markdown | **zero** | Closest peer — zero-dep markdown, but no validated index or enforced gate |
| **control-framework** | — | **plain markdown + validated index** | **zero** | **Enforced recap ritual via hooks + %5 consolidation gate + schema-validated knowledge index + ranked conflict hierarchy** |

**What's genuinely unique here** (no other tool in the niche does all of these): the recap ritual is
*enforced by hooks*, not hoped for; the every-5th-session consolidation is a *hard gate*; the knowledge
map is *schema-validated* (broken cross-refs / dupes / category mismatches fail the build); and conflicts
resolve via a *deterministic ranked hierarchy*.

**What it deliberately doesn't do:** no semantic/vector retrieval (the index is read whole — efficient to
~500 topics, not beyond), no automatic LLM extraction (the agent writes memories itself, on prompt), no
MCP server, no multi-user/team support. If you want a managed black box, pick claude-mem or mem0. If you
want a scaffold you fully understand and control, that sends nothing to a third party, this is it.

---

## How it works (the loop)

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │                          one session                                   │
  │                                                                        │
  │   SessionStart hook                              SessionEnd hook       │
  │   • reads .pending_session_writes/*              • snapshots the       │
  │   • injects "write the recap FIRST"                transcript          │
  │     into the system prompt                       • drops a flag        │
  │   • every 5th session: "consolidate FIRST"         per session         │
  └─────────┬──────────────────────────────────────────────┬─────────────┘
            │                                                │
            ▼                                                ▼
   assistant follows skills/end_of_session.md      .pending_session_writes/<id>
            │                                       .session_snapshots/<id>.jsonl
            ▼
   sessions/session_NNN.md   (≤100 lines, compacted)
   + memory/ and memory.md updated if a lasting fact changed
            │
            │  every 5th session (HARD GATE)
            ▼
   skills/weekly_consolidation.md
            │
            ▼
   knowledge/{architecture,tools,projects,processes,learnings,decisions,rules}/*.md
            │
            ▼
   scripts/build_knowledge_index.py  ──►  knowledge/INDEX.json   (validated)
            │
            ▼
   memory/MEMORY.md  ──►  injected into the NEXT session at start
```

The hooks make the ritual **non-optional**. You can't quietly start fresh work while an unwritten recap
is pending — the SessionStart hook puts that instruction at the top of the system prompt, and the %5 gate
escalates to a hard stop until the knowledge index builds clean.

---

## The three memory layers (knowledge hierarchy)

On conflict, **higher wins** — this ranking is stated in `CLAUDE.md` so the assistant resolves
contradictions deterministically:

| Rank | Layer | What it is | Lifecycle |
|---|---|---|---|
| 1 | **`knowledge/`** | Machine-readable knowledge map: 7 categories of ID'd topics + a validated `INDEX.json`. Source of truth. | Written during consolidation; never read whole — grep the index. |
| 2 | **`memory.md` + `memory/`** | Human-readable consolidated state + atomic auto-memory facts. `memory/MEMORY.md` is injected every session. | Updated each session when a lasting fact changes. |
| 3 | **`legacy/`** | Frozen old docs. Historical only — **never taken as truth.** | Append-only graveyard. |

### `knowledge/` — the 7 categories
Every topic is one markdown file with YAML frontmatter and an ID whose prefix matches its directory:

| Prefix | Dir | For |
|---|---|---|
| `ARCH` | `architecture/` | component/data-flow designs |
| `TOOL` | `tools/` | CLI, API wrappers, scripts |
| `PROJ` | `projects/<slug>/` | per-project overview + progress |
| `PROC` | `processes/` | repeatable workflows |
| `L` | `learnings/` | error → root cause → fix → lesson |
| `D` | `decisions/` | ADR-style decisions |
| `RULE` | `rules/` | universal operating rules |

```yaml
---
id: L-014
title: "Node fetch r.body is not a Web ReadableStream"
category: learnings
status: active            # active | deprecated | superseded
related: [TOOL-003, L-007] # cross-refs — validated, both directions
sessions: ["028", "029"]
tags: [node, fetch, stream]
last_verified: 2026-06-03
---
```

`scripts/build_knowledge_index.py` scans every topic, validates that IDs match directories, that
`related:` points only to existing topics, and that there are no duplicates or missing frontmatter, then
writes `knowledge/INDEX.json` with `by_category` / `by_session` / `by_tag` aggregations. **You query the
index, you never read it whole** (`grep -iE 'keyword' knowledge/INDEX.json`).

---

## What's in the box

```
control-framework/
├── CLAUDE.md                     ← assistant identity + knowledge hierarchy + rules (the system prompt)
├── memory.md                     ← consolidated human-readable state
├── README.md  LICENSE  install.sh
│
├── .claude/
│   ├── settings.json             ← hook wiring (uses $CLAUDE_PROJECT_DIR; portable)
│   └── hooks/
│       ├── session_start.sh      ← forces recap/consolidation, assigns session numbers race-free
│       ├── session_end.sh        ← snapshots transcript + drops a per-session flag
│       ├── session_pre_compact.sh ← PreCompact: snapshots the FULL transcript before compaction (no data loss)
│       └── block_git_add_all.sh  ← PreToolUse guard: blocks `git add -A`/`.` (secret-leak prevention)
│
├── skills/
│   ├── end_of_session.md         ← per-session recap ritual
│   ├── weekly_consolidation.md   ← every-5th-session distillation (HARD GATE)
│   ├── README.md  _example_skill.md
│
├── knowledge/                    ← the knowledge map (7 categories + INDEX.json)
│   ├── INDEX.json                ← generated; the searchable map
│   ├── architecture/ tools/ processes/ projects/ learnings/ decisions/ rules/
│   └── … (EXAMPLE topics, cross-linked, build clean out of the box)
│
├── memory/
│   ├── MEMORY.md                 ← one-line-per-fact index, injected every session
│   └── *.md                      ← atomic facts (type: user | feedback | project | reference)
│
├── scripts/build_knowledge_index.py   ← stdlib-only index builder + validator
├── sessions/session_000_example.md    ← compacted per-session protocols live here
├── plans/   legacy/                    ← scratch + frozen docs
└── .gitignore                          ← secrets (.env, keys/), runtime state, local settings
```

---

## Quick start

**Requirements:** [Claude Code](https://claude.com/claude-code), bash, Python 3.8+ (stdlib only — no pip).

```bash
git clone https://github.com/HenryPolycarpe/control-framework.git my-control
cd my-control
./install.sh          # fills placeholders, wires hooks, builds the index
```

Then:
1. Read `CLAUDE.md` — it's now your assistant's identity. Edit it freely.
2. Launch Claude Code **from this directory** (the hooks resolve via `$CLAUDE_PROJECT_DIR`).
3. Do some work. When you end the session, the SessionEnd hook snapshots it and queues a flag.
4. Next session, the SessionStart hook tells the assistant to write the recap first. Let it.
5. Delete the `EXAMPLE` topics in `knowledge/` and the example memories once you have real content.

### Manual install (no installer)
1. Replace every `{{PLACEHOLDER}}` in `CLAUDE.md`, `memory.md`, `memory/user_owner_role.md`.
2. Copy `.claude/settings.json` into your `.claude/settings.local.json` (or merge the `hooks` block).
3. `chmod +x .claude/hooks/*.sh scripts/*.py`
4. `python3 scripts/build_knowledge_index.py`

---

## The hooks, precisely

All three are plain bash, no dependencies, and **auto-detect the repo root** from their own location
(override with `CTRL_HOME` for testing). Claude Code passes each hook a JSON event on stdin.

- **`session_end.sh`** (SessionEnd) — copies the live transcript to `.session_snapshots/<id>.jsonl`
  *immediately* (before Claude Code can clean it up), then writes a flag file
  `.pending_session_writes/<id>` with the end timestamp and source paths. One flag per session — no
  single-file race when sessions end back-to-back.

- **`session_start.sh`** (SessionStart) — scans the flag folder, excludes the current session, dedups any
  already-recapped sessions (it greps `sessions/*.md` for the `prev_session_id:` frontmatter), assigns
  session numbers from the real `sessions/` state (race-free, only here), and injects an
  `additionalContext` block instructing the assistant to write the pending recap(s) first. On a number
  divisible by 5 it adds a **HARD GATE** demanding consolidation before any other work.

- **`session_pre_compact.sh`** (PreCompact, matcher `manual|auto`) — when a session hits the context
  limit, Claude Code truncates the history; by the time SessionEnd fires, the transcript is already the
  lossy, compacted version. PreCompact runs *just before* that, so it snapshots the richest capture of
  the session. It's a pure side-effect (PreCompact has no `additionalContext` channel — it can only
  block, which we never do): write the snapshot, allow compaction. `session_end.sh` has a no-clobber
  guard so it won't overwrite this richer snapshot with the post-compaction transcript.

- **`block_git_add_all.sh`** (PreToolUse, matcher `Bash`) — denies `git add -A` / `git add --all` /
  `git add .`. Blanket staging once swept a private SSH key into a commit; this hook is deterministic
  where a CLAUDE.md rule is merely advisory. Stage explicitly instead.

> **`prev_session_id:` is load-bearing.** Each `sessions/session_NNN.md` must carry it in frontmatter —
> it's how the SessionStart hook knows a flag was consumed and deletes it. Omit it and the same session
> is offered for recap forever. The example session and the `end_of_session` skill both show it.

---

## Security

This framework is built around **not leaking secrets**:
- `.gitignore` excludes `.env`, `keys/`, `*.pem`, `id_*`, and all runtime state.
- `block_git_add_all.sh` makes accidental blanket staging impossible.
- `settings.local.json` (machine-specific paths/permissions) is gitignored; the committed
  `settings.json` is a portable template.

When you adopt this for real work, keep credentials in `.env`/`keys/`, and treat `legacy/` as
read-only history. If you fork an instance that already has real content, **sanitize before pushing
public** — the original Control instance this was extracted from contained server hostnames, client
data, and tokens, none of which are in this template.

---

## Customizing

- **Identity & rules:** `CLAUDE.md` is the system prompt. The 4 meta-rules live there; your full
  operating canon goes in `knowledge/rules/` (it outranks everything on conflict — see the hierarchy).
- **Rituals:** add a skill per recurring multi-step task (`skills/_example_skill.md` is the shape). Good
  skills name their trigger, list ordered steps, enumerate the anti-patterns that bit you before, and end
  with a quality checklist.
- **Consolidation cadence:** the `%5` gate lives in `session_start.sh` — change the modulus to taste.
- **More hooks:** Claude Code supports `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, and more. Add
  them to `settings.json` the same way.

---

## Design principles

1. **Zero dependencies.** Bash + Python stdlib + markdown. Nothing to install, nothing to break.
2. **The ritual is enforced, not hoped for.** Hooks put the instruction in the prompt; the model can't
   skip it silently.
3. **Truth is ranked.** A strict hierarchy means contradictions resolve the same way every time.
4. **Validated, not vibes.** The index builder fails loudly on broken cross-refs, dupes, or category
   mismatches — knowledge rot is caught at build time.
5. **Append, don't overwrite.** Sessions are immutable; topics are extended; superseded docs go to
   `legacy/`. The trail always survives.

---

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, build your own assistant on it.
