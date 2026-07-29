import AgentNotchCore
import Foundation

/// agent-notch CLI — hook handler for AI coding agents
/// Usage:
///   agent-notch hook [--agent claude|codex]   Handle hook event (stdin → socket → stdout)
///   agent-notch install                        Install hooks for all agents
///   agent-notch install --development          Install hooks using this exact binary
///   agent-notch remove                         Remove hooks for all agents

Log.bootstrap()
let args = Array(CommandLine.arguments.dropFirst())
let command = AgentNotchCommand.parse(
    arguments: args,
    executablePath: CommandLine.arguments[0],
    currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
)

switch command {
case .hook(let agentType):
    HookHandler.run(agentType: agentType)

case .install(let runtime):
    do {
        try HookInstaller.install(using: runtime)
        print("Hooks installed for Claude Code and Codex CLI")
    } catch {
        fputs("Failed to install hooks: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case .remove:
    do {
        try HookInstaller.uninstall()
        print("Hooks removed for Claude Code and Codex CLI")
    } catch {
        fputs("Failed to remove hooks: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case nil:
    fputs(
        """
        agent-notch — AI coding agent monitor for macOS

        Commands:
          hook [--agent claude|codex]   Handle hook event (default: claude)
          install                        Install stable production hooks (`agent-notch`)
          install --development          Install hooks using this exact binary
          remove                         Remove hooks for all agents

        """, stderr)
    exit(1)
}
