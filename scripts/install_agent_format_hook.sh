#!/usr/bin/env bash
# Install the format-on-edit hook for Codex.
#
# Claude Code reads .claude/settings.json from the repository, so it needs no
# installation. Codex only reads ~/.codex/hooks.json, so its hook has to be
# merged into the user's home directory — which means this script must not
# clobber whatever else lives there (the notch app registers its own hooks in
# the same file; see HookInstaller).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
command="$repo/scripts/format_edited_file.sh"
hooks_file="$HOME/.codex/hooks.json"

mkdir -p "$(dirname "$hooks_file")"
[ -f "$hooks_file" ] || echo '{}' > "$hooks_file"

/usr/bin/python3 - "$hooks_file" "$command" <<'PY'
import json, sys

path, command = sys.argv[1], sys.argv[2]
with open(path) as handle:
    try:
        root = json.load(handle)
    except json.JSONDecodeError:
        raise SystemExit(f"{path} is not valid JSON; refusing to overwrite it")

hooks = root.setdefault("hooks", {})
entries = hooks.setdefault("PostToolUse", [])

# Replace our own entry rather than appending: re-running this script should be
# a no-op, and a stale path from a moved checkout must not linger.
entries = [e for e in entries if command not in json.dumps(e)]
entries = [e for e in entries if "format_edited_file.sh" not in json.dumps(e)]
entries.append({"matcher": "", "hooks": [{"type": "command", "command": command}]})
hooks["PostToolUse"] = entries

with open(path, "w") as handle:
    json.dump(root, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
print(f"installed format-on-edit hook into {path}")
PY
