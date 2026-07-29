#!/usr/bin/env bash
# Format a file an AI agent just edited.
#
# Reads the agent's PostToolUse hook payload on stdin and formats the file it
# touched, if it is a Swift file inside this repository.
#
# Wired up for Claude Code by .claude/settings.json (committed, so it applies to
# anyone working in this checkout) and for Codex by scripts/install_agent_format_hook.sh.
#
# # Why format here rather than only at commit time
# The agent reads back what it wrote. If formatting only happened at commit
# time, every file the agent re-reads would differ from what will be committed,
# and it would keep "fixing" formatting that the formatter is about to redo.
#
# Failures are swallowed: a formatter error must never block the agent's edit.
# The commit hook and CI are the gates that actually enforce formatting.
set -uo pipefail

payload="$(cat)"

# Claude Code puts the path in tool_input.file_path; Codex uses the same shape
# for its file-editing tools. Fall back across the spellings we have seen.
file="$(
  printf '%s' "$payload" | /usr/bin/python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tool_input = data.get("tool_input") or data.get("input") or {}
for key in ("file_path", "path", "filePath"):
    value = tool_input.get(key)
    if isinstance(value, str) and value:
        print(value)
        break
' 2>/dev/null
)"

[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0
case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac

repo="$(cd "$(dirname "$0")/.." && pwd)"
# Only touch files inside this repository — the agent may be editing elsewhere,
# and other projects have their own (or no) formatting rules.
case "$(cd "$(dirname "$file")" && pwd)/" in
  "$repo"/*) ;;
  *) exit 0 ;;
esac

swift format --in-place "$file" >/dev/null 2>&1 || true
exit 0
