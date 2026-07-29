#!/usr/bin/env python3
"""Dev CLI that pushes hook events straight into Agent Notch's socket.

It brings up the UI without running Claude Code / Codex for real, so it's handy for
design checks and regression passes on interrupt UI and notifications. Payloads match
the shape `AgentNotchCore/Services/ClaudeEventParser.swift` expects.

    # Replay a whole flow (session start -> tool runs -> completion notice)
    scripts/notch_event.py scenario basic

    # Show the approval banner and receive the result (approve / deny)
    scripts/notch_event.py permission --command "rm -rf build/"

    # Individual events
    scripts/notch_event.py session
    scripts/notch_event.py prompt --text "A test request"
    scripts/notch_event.py stop

Omitting `--session` uses `dev-<random>`. Pass it explicitly when you want to keep
operating on the same session.

# Sending protocol
Like the real hook, wait until the server has finished reading and closed the
connection before closing. Closing right after the send drops the event
(see `HookHandler.waitForServerToConsume`).
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timedelta, timezone
import socket
import struct
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any

SOCKET_PATH = f"/tmp/agent-notch-{os.environ.get('USER', 'unknown')}.sock"

# Events that wait for a response (the path where a GUI interaction comes back as a
# hook response). Same rule as `HookHandler.shouldWaitForResponse`.
RESPONSE_TIMEOUT = 120.0
# Upper bound on waiting for the server to read a fire-and-forget event.
CONSUME_TIMEOUT = 0.3


class SocketUnavailable(RuntimeError):
    """No socket (the app isn't running)."""


def send(payload: dict[str, Any], *, wait_for_response: bool = False) -> dict[str, Any] | None:
    """Send one event. With `wait_for_response`, wait for the GUI's reply and return it."""
    if not Path(SOCKET_PATH).exists():
        raise SocketUnavailable(
            f"{SOCKET_PATH} not found. Start the app first with `swift run AgentNotch`."
        )

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(SOCKET_PATH)
    body = json.dumps(payload).encode()
    client.sendall(struct.pack("<I", len(body)) + body)

    if wait_for_response:
        client.settimeout(RESPONSE_TIMEOUT)
        try:
            header = _recv_exactly(client, 4)
            if header is None:
                return None
            length = struct.unpack("<I", header)[0]
            data = _recv_exactly(client, length)
            return json.loads(data) if data else None
        except (TimeoutError, socket.timeout):
            return None
        finally:
            client.close()

    # Wait for the server to finish reading and close before we close (same protocol
    # as the real hook).
    client.settimeout(CONSUME_TIMEOUT)
    try:
        client.recv(16)
    except OSError:
        pass
    client.close()
    return None


def _recv_exactly(client: socket.socket, length: int) -> bytes | None:
    buffer = b""
    while len(buffer) < length:
        chunk = client.recv(length - len(buffer))
        if not chunk:
            return None
        buffer += chunk
    return buffer


def base_payload(args: argparse.Namespace, event: str) -> dict[str, Any]:
    """Fields shared by every event, including the `_pid` / `_agent_type` the hook adds."""
    payload: dict[str, Any] = {
        "hook_event_name": event,
        "session_id": args.session,
        "cwd": args.cwd,
        # The GUI tells Claude from Codex via `_agent_type` (`EventProcessor.parseMessage`).
        "_agent_type": args.agent,
        "_pid": os.getpid(),
        "_tty": os.ttyname(sys.stdin.fileno()) if sys.stdin.isatty() else None,
    }
    if args.model:
        payload["model"] = args.model
    if args.transcript:
        payload["transcript_path"] = args.transcript
    return payload


# MARK: - Individual events


def cmd_session(args: argparse.Namespace) -> None:
    send({**base_payload(args, "SessionStart"), "source": args.source})
    print(f"SessionStart session={args.session} source={args.source}")


def cmd_prompt(args: argparse.Namespace) -> None:
    send({**base_payload(args, "UserPromptSubmit"), "prompt": args.text})
    print(f"UserPromptSubmit: {args.text}")


def cmd_tool(args: argparse.Namespace) -> None:
    """Start a tool run (and carry it to completion with `--complete`)."""
    tool_use_id = args.tool_use_id or f"tool-{uuid.uuid4().hex[:8]}"
    tool_input = json.loads(args.input) if args.input else {"command": args.command}
    send({
        **base_payload(args, "PreToolUse"),
        "tool_name": args.name,
        "tool_use_id": tool_use_id,
        "tool_input": tool_input,
    })
    print(f"PreToolUse {args.name} id={tool_use_id}")

    if not args.complete:
        return
    time.sleep(args.duration)
    if args.fail:
        send({
            **base_payload(args, "PostToolUseFailure"),
            "tool_name": args.name,
            "tool_use_id": tool_use_id,
            "error": args.fail,
        })
        print(f"PostToolUseFailure {args.name}: {args.fail}")
    else:
        send({
            **base_payload(args, "PostToolUse"),
            "tool_name": args.name,
            "tool_use_id": tool_use_id,
            "tool_response": {"stdout": args.output or ""},
        })
        print(f"PostToolUse {args.name}")


def cmd_permission(args: argparse.Namespace) -> None:
    """Show the approval banner, then wait for and print the result (a round-trip check)."""
    tool_input: dict[str, Any] = {"command": args.command}
    if args.description:
        tool_input["description"] = args.description
    payload = {
        **base_payload(args, "PermissionRequest"),
        "tool_name": args.name,
        "tool_input": tool_input,
    }
    print(f"PermissionRequest {args.name}: {args.command}")
    print(f"Waiting for a response (up to {int(RESPONSE_TIMEOUT)}s)...")
    response = send(payload, wait_for_response=True)
    _report_response(response)


def cmd_question(args: argparse.Namespace) -> None:
    """Show the question banner, then wait for and print the answer."""
    if args.json:
        questions = json.loads(args.json)
    else:
        questions = [
            {
                "question": args.text,
                "header": args.header,
                "multiSelect": args.multi,
                "options": [{"label": label, "description": None} for label in args.option],
            }
        ]
    payload = {
        **base_payload(args, "PermissionRequest"),
        "tool_name": "AskUserQuestion",
        "tool_input": {"questions": questions},
    }
    print(f"AskUserQuestion: {len(questions)} question(s)")
    print(f"Waiting for an answer (up to {int(RESPONSE_TIMEOUT)}s)...")
    response = send(payload, wait_for_response=True)
    _report_response(response)


def _report_response(response: dict[str, Any] | None) -> None:
    if response is None:
        print("<- no response (timed out, or expired on the GUI side)")
        return
    print("<- response:")
    print(json.dumps(response, ensure_ascii=False, indent=2))


def cmd_notify(args: argparse.Namespace) -> None:
    send({
        **base_payload(args, "Notification"),
        "type": args.type,
        "message": args.message,
    })
    print(f"Notification[{args.type}]: {args.message}")


def cmd_stop(args: argparse.Namespace) -> None:
    if args.error:
        send({**base_payload(args, "StopFailure"), "error": args.error})
        print(f"StopFailure: {args.error}")
    else:
        send(base_payload(args, "Stop"))
        print("Stop (fires the completion notice)")


def cmd_subagent(args: argparse.Namespace) -> None:
    """Start subagents (and stop them with `--stop`). Concurrency shows up in the swarm glyph."""
    for index in range(args.count):
        agent_id = f"sub-{uuid.uuid4().hex[:6]}"
        send({
            **base_payload(args, "SubagentStart"),
            "agent_type": args.type,
            "agent_id": agent_id,
        })
        print(f"SubagentStart {args.type} id={agent_id}")
        if args.stop:
            time.sleep(args.duration)
            send({
                **base_payload(args, "SubagentStop"),
                "agent_type": args.type,
                "agent_id": agent_id,
            })
            print(f"SubagentStop id={agent_id}")
        else:
            time.sleep(0.2)
        _ = index


def cmd_task(args: argparse.Namespace) -> None:
    task_id = args.task_id or f"task-{uuid.uuid4().hex[:6]}"
    if args.complete:
        send({
            **base_payload(args, "TaskCompleted"),
            "task_id": task_id,
            "task_title": args.title,
            "completed_by": args.assignee,
            "team_name": args.team,
        })
        print(f"TaskCompleted {task_id}: {args.title}")
    else:
        send({
            **base_payload(args, "TaskCreated"),
            "task_id": task_id,
            "task_title": args.title,
            "task_description": args.description or "",
            "assigned_to": args.assignee,
            "team_name": args.team,
        })
        print(f"TaskCreated {task_id}: {args.title}")


def cmd_compact(args: argparse.Namespace) -> None:
    send(base_payload(args, "PreCompact"))
    print("PreCompact (compacting state)")
    if args.complete:
        time.sleep(args.duration)
        send(base_payload(args, "PostCompact"))
        print("PostCompact")


def cmd_teammate(args: argparse.Namespace) -> None:
    send({
        **base_payload(args, "TeammateIdle"),
        "team_name": args.team,
        "teammate_name": args.name,
        "teammate_session_id": args.teammate_session,
    })
    print(f"TeammateIdle team={args.team} teammate={args.name}")


def cmd_end(args: argparse.Namespace) -> None:
    send(base_payload(args, "SessionEnd"))
    print("SessionEnd")


# MARK: - transcript


def write_transcript(path: Path, turns: list[tuple[str, str]]) -> None:
    """Write a minimal transcript for checking the timeline in the detail view.

    Of Claude Code's JSONL format, only the fields `TranscriptReader` / `TranscriptParser`
    actually read are filled in (type / message.role / message.content / timestamp).

    Real transcripts always carry a timestamp. Dropping it hides the timeline's time
    labels, which makes it impossible to check the layout around them, so we stamp one
    per minute.
    """
    base = datetime.now(timezone.utc) - timedelta(minutes=len(turns))
    lines = []
    for index, (role, text) in enumerate(turns):
        stamp = (base + timedelta(minutes=index)).isoformat().replace("+00:00", "Z")
        lines.append(json.dumps({
            "type": role,
            "timestamp": stamp,
            "message": {
                "role": role,
                "content": [{"type": "text", "text": text}],
                # usage is for checking the cost display. Only attach it for assistant turns.
                **({"usage": {"input_tokens": 1200, "output_tokens": 320}} if role == "assistant" else {}),
                "model": "claude-opus-4",
            },
        }, ensure_ascii=False))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_transcript(args: argparse.Namespace) -> None:
    path = Path(args.path or (Path(tempfile.gettempdir()) / f"notch-dev-{args.session}.jsonl"))
    write_transcript(path, [
        ("user", "This is a dummy request."),
        ("assistant", "Got it. This is a dummy response."),
        ("user", "Here's one more."),
        ("assistant", "This one is a dummy response too."),
    ])
    print(path)


# MARK: - Scenarios


def scenario_basic(args: argparse.Namespace) -> None:
    """Start -> prompt -> two tools -> completion notice. Shows the basic notice and card."""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)

    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "This is a test request"})
    for name, command, output in [
        ("Read", "AgentNotch/UI/Root/NotchShell.swift", "lines 1..120"),
        ("Bash", "swift build", "Build complete!"),
    ]:
        tool_use_id = f"tool-{uuid.uuid4().hex[:8]}"
        send({
            **base_payload(args, "PreToolUse"),
            "tool_name": name,
            "tool_use_id": tool_use_id,
            "tool_input": {"command": command},
        })
        time.sleep(0.6)
        send({
            **base_payload(args, "PostToolUse"),
            "tool_name": name,
            "tool_use_id": tool_use_id,
            "tool_response": {"stdout": output},
        })
    time.sleep(0.3)
    send(base_payload(args, "Stop"))
    print("basic scenario done (the completion notice fires)")


def scenario_permission(args: argparse.Namespace) -> None:
    """Show the approval banner and wait. Use it to check the press animation and hotkeys."""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "Please delete the build artifacts"})
    args.name = "Bash"
    args.command = "rm -rf .build/arm64-apple-macosx/debug"
    args.description = "Delete stale build artifacts"
    cmd_permission(args)


def scenario_question(args: argparse.Namespace) -> None:
    """Show a multi-question banner and wait. Use it to check progress glyphs and tab moves."""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "Decide on an approach"})
    payload = {
        **base_payload(args, "PermissionRequest"),
        "tool_name": "AskUserQuestion",
        "tool_input": {
            "questions": [
                {
                    "question": "Which approach should we take?",
                    "header": "Design direction",
                    "multiSelect": False,
                    "options": [
                        {"label": "Incremental refactor", "description": "Swap out the internals while keeping the existing API"},
                        {"label": "Full rewrite", "description": "Accept breaking changes and rebuild from scratch"},
                    ],
                },
                {
                    "question": "Which files should be in scope?",
                    "header": None,
                    "multiSelect": True,
                    "options": [
                        {"label": "NotchShell.swift", "description": None},
                        {"label": "PermissionBanner.swift", "description": None},
                        {"label": "QuestionBanner.swift", "description": None},
                    ],
                },
            ]
        },
    }
    print("AskUserQuestion: 2 questions. Waiting for an answer...")
    _report_response(send(payload, wait_for_response=True))


def scenario_swarm(args: argparse.Namespace) -> None:
    """Start subagents in parallel and finish them in order. Checks the swarm glyph and TEAM section."""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "Look into this in parallel"})
    agent_ids = []
    for _ in range(4):
        agent_id = f"sub-{uuid.uuid4().hex[:6]}"
        agent_ids.append(agent_id)
        send({
            **base_payload(args, "SubagentStart"),
            "agent_type": "Explore",
            "agent_id": agent_id,
        })
        time.sleep(0.4)
    for agent_id in agent_ids:
        time.sleep(0.8)
        send({
            **base_payload(args, "SubagentStop"),
            "agent_type": "Explore",
            "agent_id": agent_id,
        })
    time.sleep(0.3)
    send(base_payload(args, "Stop"))
    print("swarm scenario done")


def scenario_error(args: argparse.Namespace) -> None:
    """Tool failure -> stop failure. Checks the error display (fault glyph, red)."""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "Something that should fail"})
    tool_use_id = f"tool-{uuid.uuid4().hex[:8]}"
    send({
        **base_payload(args, "PreToolUse"),
        "tool_name": "Bash",
        "tool_use_id": tool_use_id,
        "tool_input": {"command": "swift build --broken-flag"},
    })
    time.sleep(0.6)
    send({
        **base_payload(args, "PostToolUseFailure"),
        "tool_name": "Bash",
        "tool_use_id": tool_use_id,
        "error": "error: unknown option '--broken-flag'",
    })
    time.sleep(0.3)
    send({**base_payload(args, "StopFailure"), "error": "build_failed"})
    print("error scenario done")


def scenario_teams(args: argparse.Namespace) -> None:
    """Task creation and completion plus teammate idle. Checks the TEAM section and task board."""
    transcript = _prepare_transcript(args)
    args.transcript = str(transcript)
    send({**base_payload(args, "SessionStart"), "source": "startup"})
    send({**base_payload(args, "UserPromptSubmit"), "prompt": "Take this on as a team"})
    task_ids = []
    for title, assignee in [
        ("Implement the panel background", "alice"),
        ("Fix the approval banner", "bob"),
        ("Add tests", "carol"),
    ]:
        task_id = f"task-{uuid.uuid4().hex[:6]}"
        task_ids.append((task_id, title, assignee))
        send({
            **base_payload(args, "TaskCreated"),
            "task_id": task_id,
            "task_title": title,
            "task_description": "",
            "assigned_to": assignee,
            "team_name": "notch-team",
        })
        time.sleep(0.3)
    for task_id, title, assignee in task_ids[:2]:
        time.sleep(0.6)
        send({
            **base_payload(args, "TaskCompleted"),
            "task_id": task_id,
            "task_title": title,
            "completed_by": assignee,
            "team_name": "notch-team",
        })
    send({
        **base_payload(args, "TeammateIdle"),
        "team_name": "notch-team",
        "teammate_name": "alice",
        "teammate_session_id": f"{args.session}-alice",
    })
    print("teams scenario done")


SCENARIOS = {
    "basic": scenario_basic,
    "permission": scenario_permission,
    "question": scenario_question,
    "swarm": scenario_swarm,
    "error": scenario_error,
    "teams": scenario_teams,
}


def cmd_scenario(args: argparse.Namespace) -> None:
    SCENARIOS[args.name](args)


def _prepare_transcript(args: argparse.Namespace) -> Path:
    """Prepare a transcript for a scenario (uses `--transcript` when given)."""
    if args.transcript:
        return Path(args.transcript)
    path = Path(tempfile.gettempdir()) / f"notch-dev-{args.session}.jsonl"
    write_transcript(path, [
        ("user", "This is a test request"),
        ("assistant", "Understood. Starting work now."),
    ])
    return path


# MARK: - CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--session", default=f"dev-{uuid.uuid4().hex[:6]}", help="session ID")
    parser.add_argument("--cwd", default=str(Path.cwd()), help="working directory for the session")
    parser.add_argument("--agent", default="claude", choices=["claude", "codex"], help="agent type")
    parser.add_argument("--model", default="claude-opus-4", help="model name (used for cost calculation)")
    parser.add_argument("--transcript", help="transcript path (shown in the detail view timeline)")

    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("session", help="SessionStart")
    p.add_argument("--source", default="startup", choices=["startup", "resume", "clear", "compact"])
    p.set_defaults(func=cmd_session)

    p = sub.add_parser("prompt", help="UserPromptSubmit")
    p.add_argument("--text", default="This is a test request")
    p.set_defaults(func=cmd_prompt)

    p = sub.add_parser("tool", help="PreToolUse (add --complete to carry through PostToolUse)")
    p.add_argument("--name", default="Bash")
    p.add_argument("--command", default="swift build")
    p.add_argument("--input", help="specify tool_input directly as JSON")
    p.add_argument("--tool-use-id")
    p.add_argument("--complete", action="store_true", help="also send the completion event")
    p.add_argument("--fail", help="end as a failure (give the error text)")
    p.add_argument("--output", help="string to return as stdout")
    p.add_argument("--duration", type=float, default=1.0, help="seconds from start to completion")
    p.set_defaults(func=cmd_tool)

    p = sub.add_parser("permission", help="PermissionRequest (waits for a response)")
    p.add_argument("--name", default="Bash")
    p.add_argument("--command", default="rm -rf build/")
    p.add_argument("--description", default="Delete build artifacts")
    p.set_defaults(func=cmd_permission)

    p = sub.add_parser("question", help="AskUserQuestion (waits for an answer)")
    p.add_argument("--text", default="Which way should we go?")
    p.add_argument("--header", default="Direction")
    p.add_argument("--option", action="append", default=[], help="option (repeatable)")
    p.add_argument("--multi", action="store_true", help="allow multiple selection")
    p.add_argument("--json", help="specify the questions array directly as JSON")
    p.set_defaults(func=cmd_question)

    p = sub.add_parser("notify", help="Notification")
    p.add_argument("--type", default="info")
    p.add_argument("--message", default="This is a test notification")
    p.set_defaults(func=cmd_notify)

    p = sub.add_parser("stop", help="Stop (completion notice) / --error for StopFailure")
    p.add_argument("--error", help="send as a stop failure")
    p.set_defaults(func=cmd_stop)

    p = sub.add_parser("subagent", help="SubagentStart (add --stop to run through the end)")
    p.add_argument("--type", default="Explore")
    p.add_argument("--count", type=int, default=1, help="how many to start at once")
    p.add_argument("--stop", action="store_true")
    p.add_argument("--duration", type=float, default=1.0)
    p.set_defaults(func=cmd_subagent)

    p = sub.add_parser("task", help="TaskCreated / --complete for TaskCompleted")
    p.add_argument("--title", default="A dummy task")
    p.add_argument("--description")
    p.add_argument("--task-id")
    p.add_argument("--assignee")
    p.add_argument("--team")
    p.add_argument("--complete", action="store_true")
    p.set_defaults(func=cmd_task)

    p = sub.add_parser("compact", help="PreCompact (add --complete for PostCompact)")
    p.add_argument("--complete", action="store_true")
    p.add_argument("--duration", type=float, default=1.5)
    p.set_defaults(func=cmd_compact)

    p = sub.add_parser("teammate", help="TeammateIdle")
    p.add_argument("--team", default="notch-team")
    p.add_argument("--name", default="alice")
    p.add_argument("--teammate-session")
    p.set_defaults(func=cmd_teammate)

    p = sub.add_parser("end", help="SessionEnd")
    p.set_defaults(func=cmd_end)

    p = sub.add_parser("transcript", help="write a dummy transcript and print its path")
    p.add_argument("--path")
    p.set_defaults(func=cmd_transcript)

    p = sub.add_parser("scenario", help="replay a whole flow")
    p.add_argument("name", choices=sorted(SCENARIOS))
    p.set_defaults(func=cmd_scenario)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        args.func(args)
    except SocketUnavailable as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
