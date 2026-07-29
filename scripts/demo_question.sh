#!/usr/bin/env bash
# Fire a fake Claude session with a preview-carrying AskUserQuestion at the
# running AgentNotch app, to check the question banner and the preview pane by
# hand: PREVIEW badges, the `p` key, follow-focus on ↑↓, the placeholder row,
# and the top-pinned pane leaving the log and the NEXT/SEND footer intact.
#
# Prerequisites: `swift build` done and the GUI running (`swift run AgentNotch`).
# Keyboard shortcuts reach the panel only while it is engaged — click inside
# the panel once (or use the focus hotkey) before pressing `p` / arrows.
#
# The script stays in the foreground while the question is pending on purpose:
# the hook records its parent pid, and SessionSweepCoordinator drops sessions
# whose process is dead (checked every 30s) — backgrounding the hook with a
# short-lived shell makes the session vanish mid-test. Each request expires
# after the hook's 120s recv timeout; use --loop to re-fire automatically.
# Ctrl-C (or answering without --loop) ends the demo and removes the session.
#
# The session id is unique per run: the EXIT trap sends SessionEnd, and a
# shared id would let a finishing run remove the session a newer run just
# created.
#
# Usage:
#   scripts/demo_question.sh          # fire once, wait for the answer
#   scripts/demo_question.sh --loop   # re-fire whenever the request expires

set -euo pipefail
cd "$(dirname "$0")/.."

BIN=.build/debug/agent-notch
if [[ ! -x "$BIN" ]]; then
  echo "error: $BIN not found — run 'swift build' first" >&2
  exit 1
fi

SESSION_ID="preview-demo-$$"

session_start() {
  "$BIN" hook --agent claude <<JSON
{"hook_event_name":"SessionStart","session_id":"$SESSION_ID","cwd":"$PWD","source":"startup"}
JSON
}

session_end() {
  "$BIN" hook --agent claude >/dev/null 2>&1 <<JSON || true
{"hook_event_name":"SessionEnd","session_id":"$SESSION_ID"}
JSON
}
trap session_end EXIT

# Question 1 carries ASCII previews on A/B and none on C (placeholder check).
# Question 2 has no previews at all, so the "P Preview" key hint must disappear.
ask_question() {
  "$BIN" hook --agent claude <<JSON
{
  "hook_event_name": "PermissionRequest",
  "session_id": "$SESSION_ID",
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [
      {
        "question": "Which layout should the session list card use?",
        "header": "Layout",
        "multiSelect": false,
        "options": [
          {
            "label": "A: Three columns",
            "description": "State glyph left, info center, actions right",
            "preview": "┌──────────────────────────────────────────────────────┐\n│ [◍] sample-web  feat/onboarding  [PLAN]          92s ⋯│\n│  C  Waiting — Bash rm -rf .next/cache  [Approve][Deny]│\n│     ◧◧◧◨ 2/4 TASKS · 18.2K TOK · \$0.42                │\n└──────────────────────────────────────────────────────┘"
          },
          {
            "label": "B: Two stacked rows",
            "description": "Identity on top, meta values below",
            "preview": "┌──────────────────────────────────────────────────────┐\n│ sample-web · feat/onboarding · [PLAN] · C        92s  │\n│ ──────────────────────────────────────────────────── │\n│ Waiting — Bash rm -rf .next/cache                     │\n│ ◧◧◧◨ 2/4 TASKS · 18.2K TOK · \$0.42     [Approve][Deny]│\n└──────────────────────────────────────────────────────┘"
          },
          {
            "label": "C: Single compact line",
            "description": "Option without a preview (placeholder check)"
          }
        ]
      },
      {
        "question": "Check: the P key hint must disappear on a question without previews",
        "header": "Check",
        "multiSelect": false,
        "options": [
          {"label": "OK", "description": "This question has no previews"},
          {"label": "NG", "description": "The P hint is still showing"}
        ]
      }
    ]
  }
}
JSON
}

echo "-> SessionStart ($SESSION_ID)"
session_start

if [[ "${1:-}" == "--loop" ]]; then
  while true; do
    echo "-> AskUserQuestion (answer it or it expires in 120s and re-fires; Ctrl-C to quit)"
    ask_question || true
    sleep 1
  done
else
  echo "-> AskUserQuestion (answer in the notch to see the response JSON below; waits up to 120s)"
  ask_question || true
fi
