import AgentNotchCore
import Foundation

/// agent-notch CLI — hook handler for Claude Code
/// Usage:
///   agent-notch hook     Read hook event from stdin, forward to socket, print response
///   agent-notch install  Install hooks into ~/.claude/settings.json
///   agent-notch remove   Remove hooks from ~/.claude/settings.json

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "hook"

switch command {
case "hook":
    HookHandler.run()

case "install":
    HookInstaller.installCLI()
    print("Hooks installed into ~/.claude/settings.json")

case "remove":
    HookInstaller.uninstall()
    print("Hooks removed from ~/.claude/settings.json")

default:
    fputs("""
    agent-notch — AI coding agent monitor for macOS

    Commands:
      hook      Handle a Claude Code hook event (reads stdin, writes stdout)
      install   Install hooks into ~/.claude/settings.json
      remove    Remove hooks from ~/.claude/settings.json

    """, stderr)
    exit(1)
}
