# Development scripts

## `notch_event.py` — inject hook events directly

A CLI that sends hook events to Agent Notch's Unix socket so you can **exercise the UI without actually running Claude Code or Codex**. Interrupt UI (approvals, questions) and notifications depend on agent state, which is tedious to reproduce by hand. Use this for design review and regression checks.

Prerequisite: the app is running (`swift run AgentNotch`); the socket is at `/tmp/agent-notch-$USER.sock`.

### Start here

```bash
# A full flow (create session -> prompt -> two tools -> completion notification)
scripts/notch_event.py scenario basic

# Show the approval banner and receive the result of the button press
scripts/notch_event.py scenario permission

# Show the question banner (two questions) and receive the answers
scripts/notch_event.py scenario question
```

`permission` and `question` wait for the GUI to respond, so they block until you click (up to 120 s). They print the hook response verbatim, which **confirms the round trip actually works**.

### Scenarios

| Name | What it exercises |
| --- | --- |
| `basic` | Baseline notification and session card |
| `permission` | Approval banner, press animation, hotkeys (⌥⇧⏎ / ⌥⇧⌫) |
| `question` | Question banner, progress glyph, tab transitions |
| `swarm` | Concurrent subagents (swarm glyph) |
| `error` | Tool failure and stop failure (fault glyph, red) |
| `teams` | Task board and TEAM section |

### Individual events

```bash
scripts/notch_event.py session                       # SessionStart
scripts/notch_event.py prompt --text "please fix it"  # UserPromptSubmit
scripts/notch_event.py tool --name Bash --command "swift build" --complete
scripts/notch_event.py tool --name Edit --complete --fail "permission denied"
scripts/notch_event.py permission --command "rm -rf build/"
scripts/notch_event.py question --option A --option B --multi
scripts/notch_event.py notify --type info --message "a notification"
scripts/notch_event.py subagent --count 3            # 3 running in parallel
scripts/notch_event.py task --title "a task" --assignee alice --team notch-team
scripts/notch_event.py compact --complete            # compacting -> done
scripts/notch_event.py teammate --name alice
scripts/notch_event.py stop                          # Completion notification
scripts/notch_event.py stop --error build_failed     # Stop failure
scripts/notch_event.py end                           # SessionEnd
```

`--help` lists every option, and it works per subcommand too: `scripts/notch_event.py tool --help`.

### Driving a single session

Without `--session` every invocation gets a fresh ID. Pin it when you want to follow state transitions.

```bash
S=my-test
scripts/notch_event.py --session $S session
scripts/notch_event.py --session $S prompt --text "please investigate"
scripts/notch_event.py --session $S subagent --count 2      # Shows as running
scripts/notch_event.py --session $S stop                    # Completion notification
```

### Viewing the detail-page timeline

Chat rendering needs a transcript, so write out a dummy one and pass it in.

```bash
T=$(scripts/notch_event.py --session my-test transcript)
scripts/notch_event.py --session my-test --transcript "$T" session
```

Scenarios generate their own dummy transcript, so you don't need to pass one.

### Sending as Codex

```bash
scripts/notch_event.py --agent codex scenario basic
```

This sets `_agent_type` to `codex`, so the logo and accent color switch to Codex.

## Implementation notes

**Do not close immediately after sending.** The server (`NWConnection`) only arms its receive after the `.ready` notification, so a FIN that arrives before that discards the data even if it is already sitting in the kernel buffer. Like the real hook (`HookHandler.waitForServerToConsume`), this script waits for the server to finish reading and close the connection before closing its own end.

`AgentNotchCore/Services/ClaudeEventParser.swift` is the single source of truth for payload shapes. When you add an event, match its `switch`. Anything the GUI cannot interpret is silently dropped as `unknown` (visible as `← [UNKNOWN hook]` when running with `AGENT_NOTCH_LOG=debug`).
