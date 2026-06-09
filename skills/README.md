# skills/

**Skills are markdown playbooks** the assistant follows for repeatable, multi-step rituals. They are not
code — they're checklists with rules, anti-patterns, and quality gates. The assistant reads the relevant
one when its trigger fires.

## Core skills (part of the compound-memory machine — keep these)
- **`end_of_session.md`** — write the recap for each finished session. Triggered by the SessionStart hook.
- **`weekly_consolidation.md`** — every 5th session, distill raw sessions into the knowledge map.

## Your own skills
Add one markdown file per ritual you do more than twice. Good skills:
- name the **trigger** ("when the owner asks for X"),
- list **steps in order**,
- enumerate **anti-patterns** (what went wrong before),
- end with a **quality checklist** before "done".

See `_example_skill.md` for the shape. The SSOT-briefing skill in the original Control instance is a good
real-world example: it codified the exact source pipeline + quality checks so a recurring deliverable
stopped dropping data.
