#!/usr/bin/env python3
"""
build_knowledge_index.py — Scans _control/knowledge/**/*.md, parses YAML frontmatter,
writes _control/knowledge/INDEX.json.

Cron (daily 03:17 local):
  17 3 * * * cd /path/to/your/control && /usr/bin/python3 scripts/build_knowledge_index.py >> .claude/hooks/build_index.log 2>&1

Exit codes:
  0  no problems (or knowledge dir empty)
  1  problems detected (broken_refs / duplicates / missing_frontmatter / category mismatch)

INDEX.json is ALWAYS written, regardless of exit code.

Only stdlib — uses a tiny self-contained YAML frontmatter parser (the subset we need:
key: value, key: [a, b], key: "value", lists as inline arrays).
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
CONTROL_DIR = SCRIPT_DIR.parent
KNOWLEDGE_DIR = CONTROL_DIR / "knowledge"
INDEX_PATH = KNOWLEDGE_DIR / "INDEX.json"

# ID prefix → expected category directory
CATEGORY_PREFIXES = {
    "ARCH": "architecture",
    "TOOL": "tools",
    "PROJ": "projects",
    "PROC": "processes",
    "L":    "learnings",
    "D":    "decisions",
    "RULE": "rules",
}
# Inverse: dir → allowed prefixes (a dir can in theory hold multiple, but we keep 1:1)
DIR_TO_PREFIX = {v: k for k, v in CATEGORY_PREFIXES.items()}

ID_RE = re.compile(r"^([A-Z]+)-(\d+)$")


# ---------------------------------------------------------------------------
# Minimal YAML frontmatter parser
# ---------------------------------------------------------------------------
def parse_frontmatter(text: str) -> dict | None:
    """Return dict or None if no frontmatter present."""
    if not text.startswith("---"):
        return None
    # Find closing ---
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None
    body = lines[1:end]
    return _parse_yaml_block(body)


def _parse_yaml_block(lines: list[str]) -> dict:
    """
    Tiny YAML-ish parser. Supports:
      key: value
      key: "value"
      key: 'value'
      key: [a, b, "c"]
      key:
        - a
        - b
        - "c"
    Ignores comments. Returns dict with str/list[str] values.
    """
    result: dict = {}
    current_key: str | None = None
    current_list: list | None = None

    for raw in lines:
        # Strip trailing comments only if not inside quotes (keep simple — strip after #)
        line = raw.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue

        # List item (continuation)
        m_item = re.match(r"^\s+-\s*(.*)$", line)
        if m_item and current_list is not None:
            current_list.append(_unquote(m_item.group(1).strip()))
            continue

        # New key
        m_kv = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", line)
        if m_kv:
            key = m_kv.group(1).strip()
            val = m_kv.group(2).strip()
            current_key = key
            current_list = None

            if val == "":
                # Block list incoming
                result[key] = []
                current_list = result[key]
                continue

            if val.startswith("[") and val.endswith("]"):
                inner = val[1:-1].strip()
                if not inner:
                    result[key] = []
                else:
                    result[key] = [_unquote(x.strip()) for x in _split_inline_list(inner)]
                continue

            result[key] = _unquote(val)
            continue
        # Unknown line — ignore
    return result


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


def _split_inline_list(s: str) -> list[str]:
    """Split a, b, "c, d", e respecting quotes."""
    out, buf, in_q, q = [], [], False, ""
    for ch in s:
        if in_q:
            buf.append(ch)
            if ch == q:
                in_q = False
        else:
            if ch in ("'", '"'):
                in_q = True
                q = ch
                buf.append(ch)
            elif ch == ",":
                out.append("".join(buf).strip())
                buf = []
            else:
                buf.append(ch)
    if buf:
        out.append("".join(buf).strip())
    return [x for x in out if x]


# ---------------------------------------------------------------------------
# Main scan
# ---------------------------------------------------------------------------
def build_index() -> tuple[dict, bool]:
    """Returns (index_dict, ok_flag)."""
    topics: list[dict] = []
    missing_frontmatter: list[str] = []
    duplicates: list[str] = []
    broken_refs: list[dict] = []
    seen_ids: dict[str, str] = {}  # id -> path

    if KNOWLEDGE_DIR.exists():
        md_files = sorted(KNOWLEDGE_DIR.rglob("*.md"))
    else:
        md_files = []

    # First pass: collect topics
    for md in md_files:
        rel = md.relative_to(CONTROL_DIR).as_posix()
        try:
            text = md.read_text(encoding="utf-8")
        except Exception:
            missing_frontmatter.append(rel)
            continue
        fm = parse_frontmatter(text)
        if fm is None or "id" not in fm:
            missing_frontmatter.append(rel)
            continue

        tid = str(fm.get("id", "")).strip()
        if not tid:
            missing_frontmatter.append(rel)
            continue

        topic = {
            "id": tid,
            "title": fm.get("title", ""),
            "category": fm.get("category", ""),
            "path": rel,
            "status": fm.get("status", ""),
            "related": _as_list(fm.get("related", [])),
            "sessions": _as_list(fm.get("sessions", [])),
            "tags": _as_list(fm.get("tags", [])),
            "last_verified": fm.get("last_verified", ""),
        }
        topics.append(topic)

        if tid in seen_ids:
            duplicates.append(tid)
        else:
            seen_ids[tid] = rel

    # Validate category vs ID prefix + collect existing IDs for ref-check
    existing_ids = set(t["id"] for t in topics)

    for t in topics:
        m = ID_RE.match(t["id"])
        if m:
            prefix = m.group(1)
            expected_dir = CATEGORY_PREFIXES.get(prefix)
            # Path contains "knowledge/<category>/..."
            parts = t["path"].split("/")
            actual_dir = parts[1] if len(parts) >= 3 and parts[0] == "knowledge" else ""
            if expected_dir and actual_dir and expected_dir != actual_dir:
                broken_refs.append({
                    "from": t["id"],
                    "to": f"category-mismatch:expected={expected_dir},actual={actual_dir}",
                })
            if t["category"] and expected_dir and t["category"] != expected_dir:
                broken_refs.append({
                    "from": t["id"],
                    "to": f"frontmatter-category-mismatch:expected={expected_dir},got={t['category']}",
                })

        # related[] → must point to existing IDs
        for ref in t["related"]:
            if ref and ref not in existing_ids:
                broken_refs.append({"from": t["id"], "to": ref})

    # Aggregations
    by_category: dict[str, list[str]] = {}
    by_session: dict[str, list[str]] = {}
    by_tag: dict[str, list[str]] = {}

    for t in topics:
        cat = t["category"] or "unknown"
        by_category.setdefault(cat, []).append(t["id"])
        for s in t["sessions"]:
            by_session.setdefault(str(s), []).append(t["id"])
        for tag in t["tags"]:
            by_tag.setdefault(str(tag), []).append(t["id"])

    for d in (by_category, by_session, by_tag):
        for k in d:
            d[k] = sorted(set(d[k]))

    orphans = sorted(t["id"] for t in topics if not t["related"])

    # Staleness (warning ONLY, does not affect ok/exit code): last_verified older than 30 days
    # or missing/unparseable. Surface it so the precedence rule ("newer last_verified beats
    # older") doesn't run on stale data.
    today = datetime.now(timezone.utc).date()
    stale_topics: list[dict] = []
    no_last_verified: list[str] = []
    for t in topics:
        lv = str(t["last_verified"] or "").strip()
        if not lv:
            no_last_verified.append(t["id"])
            continue
        try:
            age = (today - datetime.strptime(lv[:10], "%Y-%m-%d").date()).days
        except ValueError:
            no_last_verified.append(t["id"])
            continue
        if age > 30:
            stale_topics.append({"id": t["id"], "last_verified": lv, "age_days": age})
    stale_topics.sort(key=lambda x: -x["age_days"])

    index = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "topics": sorted(topics, key=lambda x: x["id"]),
        "by_category": dict(sorted(by_category.items())),
        "by_session": dict(sorted(by_session.items())),
        "by_tag": dict(sorted(by_tag.items())),
        "orphans": orphans,
        "stale_topics": stale_topics,
        "no_last_verified": sorted(no_last_verified),
        "broken_refs": broken_refs,
        "duplicates": sorted(set(duplicates)),
        "missing_frontmatter": sorted(missing_frontmatter),
    }

    ok = not (broken_refs or duplicates or missing_frontmatter)
    return index, ok


def _as_list(v) -> list[str]:
    if v is None or v == "":
        return []
    if isinstance(v, list):
        return [str(x) for x in v if str(x).strip()]
    return [str(v)]


# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
def main() -> int:
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    index, ok = build_index()
    INDEX_PATH.write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    n = len(index["topics"])
    print(
        f"{n} topics indexed, "
        f"{len(index['orphans'])} orphans, "
        f"{len(index['broken_refs'])} broken refs, "
        f"{len(index['duplicates'])} duplicates, "
        f"{len(index['missing_frontmatter'])} missing-frontmatter "
        f"→ {INDEX_PATH.relative_to(CONTROL_DIR)}"
    )
    if index["stale_topics"] or index["no_last_verified"]:
        print(
            f"WARN (non-fatal): {len(index['stale_topics'])} topics last_verified >30d, "
            f"{len(index['no_last_verified'])} with missing/unparseable last_verified "
            f"(details in INDEX.json: stale_topics / no_last_verified)"
        )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
