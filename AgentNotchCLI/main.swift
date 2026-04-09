import AgentNotchCore
import Foundation

/// agent-notch CLI — hook handler for AI coding agents
/// Usage:
///   agent-notch hook [--agent claude|codex]   Handle hook event (stdin → socket → stdout)
///   agent-notch install                        Install hooks for all agents
///   agent-notch remove                         Remove hooks for all agents

Log.bootstrap()
let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "hook"

switch command {
case "hook":
    // Parse --agent flag (default: claude)
    var agentType = "claude"
    if let idx = args.firstIndex(of: "--agent"), idx + 1 < args.count {
        agentType = args[idx + 1]
    }
    HookHandler.run(agentType: agentType)

case "install":
    HookInstaller.installCLI()
    print("Hooks installed for Claude Code and Codex CLI")

case "remove":
    HookInstaller.uninstall()
    print("Hooks removed for Claude Code and Codex CLI")

default:
    fputs("""
    agent-notch — AI coding agent monitor for macOS

    Commands:
      hook [--agent claude|codex]   Handle hook event (default: claude)
      install                        Install hooks for all agents
      remove                         Remove hooks for all agents

    """, stderr)
    exit(1)
}
