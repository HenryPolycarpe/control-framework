#!/usr/bin/env bash
# install.sh — set up a fresh Control instance from this template.
# - Fills the {{PLACEHOLDER}} values in CLAUDE.md / memory.md / memory/*.md
# - Creates the runtime state dirs
# - Wires the hooks into your .claude/settings.local.json (or tells you how)
# - Builds the knowledge index
#
# Safe to re-run. It never overwrites files you've already customized (it only substitutes
# remaining {{PLACEHOLDERS}} and creates missing dirs).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "Control framework installer"
echo "Repo root: $ROOT"
echo

# --- collect values -------------------------------------------------------
prompt() { local var="$1" label="$2" def="${3:-}"; local val
  if [ -n "$def" ]; then read -rp "$label [$def]: " val; val="${val:-$def}";
  else read -rp "$label: " val; fi
  printf -v "$var" '%s' "$val"
}

ASSISTANT_NAME=""; OWNER_NAME=""; OWNER_CONTACT=""
prompt ASSISTANT_NAME "Assistant name (e.g. Control)" "Control"
prompt OWNER_NAME     "Owner name"
prompt OWNER_CONTACT  "Owner contact (email)"
CONTROL_HOME="$ROOT"

echo
echo "Substituting placeholders ..."
# Substitute in the human-authored files only (not this script, not the knowledge examples you may delete).
FILES=(CLAUDE.md memory.md memory/user_owner_role.md)
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  python3 - "$f" "$ASSISTANT_NAME" "$OWNER_NAME" "$OWNER_CONTACT" "$CONTROL_HOME" <<'PY'
import sys
f, a, o, c, h = sys.argv[1:6]
s = open(f, encoding="utf-8").read()
s = (s.replace("{{ASSISTANT_NAME}}", a)
       .replace("{{OWNER_NAME}}", o)
       .replace("{{OWNER_CONTACT}}", c)
       .replace("{{CONTROL_HOME}}", h))
open(f, "w", encoding="utf-8").write(s)
print("  patched", f)
PY
done

# --- runtime dirs ---------------------------------------------------------
echo
echo "Creating runtime state dirs ..."
mkdir -p .pending_session_writes .session_snapshots .claude/hooks plans legacy
chmod +x .claude/hooks/*.sh scripts/*.py 2>/dev/null || true

# --- hooks ----------------------------------------------------------------
echo
echo "Wiring hooks ..."
SETTINGS=".claude/settings.local.json"
if [ -f "$SETTINGS" ]; then
  echo "  $SETTINGS already exists — leaving it. Merge the 'hooks' block from .claude/settings.json yourself."
else
  cp .claude/settings.json "$SETTINGS"
  echo "  copied .claude/settings.json -> $SETTINGS"
  echo "  (the hook commands use \$CLAUDE_PROJECT_DIR, so they work as long as you launch Claude Code from this dir)"
fi

# --- index ----------------------------------------------------------------
echo
echo "Building knowledge index ..."
python3 scripts/build_knowledge_index.py || true

cat <<EOF

Done.

Next:
  1. Open CLAUDE.md and read it — it's now yours.
  2. Delete the EXAMPLE topics in knowledge/ and the example memories once you have real content.
  3. Launch Claude Code from this directory. The SessionStart hook runs on start; finish a session
     and the SessionEnd hook will queue the first real recap.
  4. Keep secrets in .env / keys/ — both are gitignored. Never commit them.
EOF
