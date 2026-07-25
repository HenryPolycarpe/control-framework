#!/usr/bin/env bash
# install.sh — turn this template into YOUR own Control instance.
#
#   ./install.sh                          # zero questions: sensible defaults from git config
#   ./install.sh --owner "Jane" --contact jane@example.com --assistant Jarvis
#   ./install.sh --clean-examples         # also delete the EXAMPLE knowledge topics
#
# Runs non-interactively by default — an agent, a pipe or CI can execute it without hanging.
# Safe to re-run: it only fills remaining {{PLACEHOLDERS}}, creates missing dirs, never
# overwrites content you have already written.
#
# What it does:
#   1. fills {{PLACEHOLDERS}} in CLAUDE.md / memory.md / memory/user_owner_role.md
#   2. detaches `origin` if it still points at the framework template  (<- important: your
#      memory must never be pushed to the public template repo)
#   3. creates the runtime dirs, makes hooks executable
#   4. builds the knowledge index
#   5. runs scripts/selftest.sh — so you SEE the loop working before you start
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

ASSISTANT_NAME="${CONTROL_ASSISTANT:-}"
OWNER_NAME="${CONTROL_OWNER:-}"
OWNER_CONTACT="${CONTROL_CONTACT:-}"
CLEAN_EXAMPLES=0
RUN_SELFTEST=1
ASSUME_YES=0

usage(){ sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --assistant) ASSISTANT_NAME="${2:-}"; shift 2;;
    --owner)     OWNER_NAME="${2:-}";     shift 2;;
    --contact)   OWNER_CONTACT="${2:-}";  shift 2;;
    --clean-examples) CLEAN_EXAMPLES=1; shift;;
    --no-selftest)    RUN_SELFTEST=0;   shift;;
    -y|--yes)         ASSUME_YES=1;     shift;;
    -h|--help)        usage;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2;;
  esac
done

# --- values: flags > env > git config > defaults ---------------------------
[ -n "$OWNER_NAME" ]    || OWNER_NAME="$(git config user.name  2>/dev/null || true)"
[ -n "$OWNER_CONTACT" ] || OWNER_CONTACT="$(git config user.email 2>/dev/null || true)"
[ -n "$ASSISTANT_NAME" ] || ASSISTANT_NAME="Control"
[ -n "$OWNER_NAME" ]    || OWNER_NAME="the owner"
[ -n "$OWNER_CONTACT" ] || OWNER_CONTACT="(not set)"

# Ask only when a human is actually sitting there AND didn't pass --yes.
if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
  read -rp "Assistant name [$ASSISTANT_NAME]: " _a || true; [ -n "${_a:-}" ] && ASSISTANT_NAME="$_a"
  read -rp "Owner name [$OWNER_NAME]: "       _o || true; [ -n "${_o:-}" ] && OWNER_NAME="$_o"
  read -rp "Owner contact [$OWNER_CONTACT]: " _c || true; [ -n "${_c:-}" ] && OWNER_CONTACT="$_c"
fi

echo "Control framework installer"
echo "  root:      $ROOT"
echo "  assistant: $ASSISTANT_NAME"
echo "  owner:     $OWNER_NAME <$OWNER_CONTACT>"
echo

# --- 1. placeholders -------------------------------------------------------
echo "Substituting placeholders ..."
python3 - "$ASSISTANT_NAME" "$OWNER_NAME" "$OWNER_CONTACT" "$ROOT" <<'PY'
import sys, pathlib, re
a, o, c, h = sys.argv[1:5]
# The template banners are blockquotes that mention {{PLACEHOLDER}} themselves — drop them once
# the file is personalized, otherwise every instance keeps claiming to be an untouched template.
BANNER = re.compile(r"^> (?:This is a \*\*template\*\*|EXAMPLE memory of type).*(?:\n> .*)*\n+", re.M)
for name in ("CLAUDE.md", "memory.md", "memory/user_owner_role.md"):
    p = pathlib.Path(name)
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8")
    n = (BANNER.sub("", s)
          .replace("{{ASSISTANT_NAME}}", a)
          .replace("{{OWNER_NAME}}", o)
          .replace("{{OWNER_CONTACT}}", c)
          .replace("{{CONTROL_HOME}}", h))
    if n != s:
        p.write_text(n, encoding="utf-8")
        print("  patched", name)
    else:
        print("  unchanged (already personalized)", name)
PY

# --- 2. detach the template remote ----------------------------------------
# A fresh clone points at the public framework repo. Auto-push in session_end.sh would then
# try to send YOUR sessions and memories there. Detach it; the user sets their own remote.
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || echo "")"
case "$ORIGIN_URL" in
  *control-framework*)
    git remote remove origin 2>/dev/null \
      && echo "Detached template remote ($ORIGIN_URL)." \
      || echo "WARN: could not remove the template remote — do it by hand: git remote remove origin"
    echo "  -> create your OWN (private!) repo and run: git remote add origin <your-repo-url>"
    ;;
  "") echo "No git remote configured — purely local. Fine; add one later for multi-machine sync.";;
  *)  echo "Remote origin: $ORIGIN_URL (kept).";;
esac

# --- 3. runtime dirs + permissions ----------------------------------------
echo
echo "Creating runtime state dirs ..."
mkdir -p .pending_session_writes .session_snapshots plans legacy
chmod +x .claude/hooks/*.sh scripts/*.sh scripts/*.py 2>/dev/null || true
echo "  ok"

# Hooks live in the committed .claude/settings.json and are picked up automatically when you
# launch Claude Code from this directory. Do NOT copy that block into settings.local.json —
# both files are loaded and merged, so the hooks would be registered (and fire) twice.
echo
echo "Hooks: registered via .claude/settings.json (\$CLAUDE_PROJECT_DIR — portable)."
echo "  Claude Code asks you once to trust this project's hooks. Say yes, otherwise nothing runs."

# --- 4. examples -----------------------------------------------------------
if [ "$CLEAN_EXAMPLES" -eq 1 ]; then
  echo
  echo "Removing EXAMPLE content ..."
  # Delete every topic tagged `example`, then strip dangling cross-refs to them, so the index
  # still builds green afterwards. Topics tagged `real` (like L-002) are kept on purpose.
  python3 - <<'PY'
import pathlib, re
kn = pathlib.Path("knowledge")
victims = {}
for p in kn.rglob("*.md"):
    head = p.read_text(encoding="utf-8").split("---")[1] if p.read_text(encoding="utf-8").startswith("---") else ""
    m_id = re.search(r"^id:\s*(\S+)", head, re.M)
    m_tags = re.search(r"^tags:\s*\[(.*?)\]", head, re.M)
    tags = [t.strip() for t in (m_tags.group(1).split(",") if m_tags else [])]
    if m_id and "example" in tags:
        victims[m_id.group(1)] = p
for tid, p in victims.items():
    p.unlink(); print("  removed", p)
for p in kn.rglob("*.md"):
    s = p.read_text(encoding="utf-8")
    m = re.search(r"^related:\s*\[(.*?)\]", s, re.M)
    if not m:
        continue
    keep = [r.strip() for r in m.group(1).split(",") if r.strip() and r.strip() not in victims]
    new = f"related: [{', '.join(keep)}]"
    if new != m.group(0):
        p.write_text(s[:m.start()] + new + s[m.end():], encoding="utf-8")
        print("  cleaned refs in", p)
for d in (kn / "projects").glob("example-project"):
    import shutil; shutil.rmtree(d); print("  removed", d)
PY
  rm -f skills/_example_skill.md sessions/session_000_example.md
  echo "  examples gone — your knowledge map starts empty."
fi

# --- 5. index --------------------------------------------------------------
echo
echo "Building knowledge index ..."
python3 scripts/build_knowledge_index.py || echo "  (index reported problems — see above)"

# --- 6. proof --------------------------------------------------------------
if [ "$RUN_SELFTEST" -eq 1 ] && [ -f scripts/selftest.sh ]; then
  echo
  bash scripts/selftest.sh || {
    echo
    echo "Self-test FAILED — fix the reported checks before relying on this instance." >&2
    exit 1
  }
fi

cat <<EOF

Done. Next:
  1. Read CLAUDE.md — that's your assistant's identity now. Edit it freely.
  2. Launch Claude Code from THIS directory (the hooks resolve via \$CLAUDE_PROJECT_DIR).
  3. Work a session, then end it. The next start will make the assistant write the recap first.
  4. Keep secrets in .env / keys/ (both gitignored). Never commit them.
EOF
