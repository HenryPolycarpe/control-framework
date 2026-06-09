# memory.md — consolidated state

> The single human-readable "where things stand" file. The assistant reads this for current state;
> it points into `knowledge/` for detail and does NOT duplicate topic content. Keep it tight.

## 1. Identity
- Assistant: **{{ASSISTANT_NAME}}** · Owner: **{{OWNER_NAME}}** ({{OWNER_CONTACT}})
- Control home: `{{CONTROL_HOME}}`
- Knowledge hierarchy (on conflict): `knowledge/` > `memory.md` + `memory/` > `legacy/`

## 2. Current state
### Live projects / services
- _(none yet — add one line per live project, pointer into `knowledge/projects/<slug>/`)_

### Infrastructure
- _(server(s), services, deploy targets, tunnels — short)_

### Frozen / archived
- _(things deliberately not touched)_

### Open threads
- _(what the next session should pick up)_

## 3. Lessons learned (pointers only)
- See `knowledge/learnings/` (L-*) and `knowledge/rules/` (RULE-*).

## 4. Session index
| Session | Date | Summary |
|---|---|---|
| 000 | (example) | template scaffolded — see `sessions/session_000_example.md` |
