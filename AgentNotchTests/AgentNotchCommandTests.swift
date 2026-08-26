import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Agent Notch command parsing")
struct AgentNotchCommandTests {
    private let cwd = URL(fileURLWithPath: "/tmp/project", isDirectory: true)

    @Test("No arguments defaults to the Claude hook")
    func defaultCommand() {
        let command = parse([])

        #expect(command == .hook(agentType: "claude"))
    }

    @Test("Hook accepts an explicit agent")
    func explicitHookAgent() {
        let command = parse(["hook", "--agent", "codex"])

        #expect(command == .hook(agentType: "codex"))
    }

    @Test("A missing agent value keeps the Claude default")
    func missingHookAgentValue() {
        let command = parse(["hook", "--agent"])

        #expect(command == .hook(agentType: "claude"))
    }

    @Test("Install defaults to the production runtime")
    func productionInstall() {
        let command = parse(["install"])

        #expect(command == .install(runtime: .production))
    }

    @Test("Development install resolves a relative executable path")
    func developmentInstall() {
        let command = parse(
            ["install", "--development"],
            executablePath: ".build/debug/agent-notch"
        )

        #expect(
            command
                == .install(
                    runtime: .development(
                        executablePath: "/tmp/project/.build/debug/agent-notch"
                    )
                )
        )
    }

    @Test("Remove maps to the removal command")
    func remove() {
        #expect(parse(["remove"]) == .remove)
    }

    @Test("Unknown commands are rejected")
    func unknownCommand() {
        #expect(parse(["unknown"]) == nil)
    }

    private func parse(
        _ arguments: [String],
        executablePath: String = "/usr/local/bin/agent-notch"
    ) -> AgentNotchCommand? {
        AgentNotchCommand.parse(
            arguments: arguments,
            executablePath: executablePath,
            currentDirectory: cwd
        )
    }
}
