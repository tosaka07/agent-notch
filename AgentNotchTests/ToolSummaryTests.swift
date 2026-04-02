import Foundation
import Testing
@testable import AgentNotch

@Suite("ToolSummary Tests")
struct ToolSummaryTests {
    @Test("Bash command is shown directly")
    func bashNormal() {
        let result = ToolSummary.generate(
            toolName: "Bash",
            toolInput: ["command": "ls -la"]
        )
        #expect(result == "ls -la")
    }

    @Test("Long Bash command is truncated to 30 chars")
    func bashLong() {
        let longCommand = "find /usr/local/bin -name '*.sh' -exec chmod +x {} \\;"
        let result = ToolSummary.generate(
            toolName: "Bash",
            toolInput: ["command": longCommand]
        )
        #expect(result.count == 33) // 30 + "..."
        #expect(result.hasSuffix("..."))
    }

    @Test("Edit shows file name")
    func editFile() {
        let result = ToolSummary.generate(
            toolName: "Edit",
            toolInput: ["file_path": "/Users/dev/project/main.swift"]
        )
        #expect(result == "main.swift")
    }

    @Test("Grep shows quoted pattern")
    func grepPattern() {
        let result = ToolSummary.generate(
            toolName: "Grep",
            toolInput: ["pattern": "TODO"]
        )
        #expect(result == "\"TODO\"")
    }

    @Test("WebSearch truncates long query")
    func webSearchLong() {
        let result = ToolSummary.generate(
            toolName: "WebSearch",
            toolInput: ["query": "how to implement async await in Swift"]
        )
        #expect(result.count == 23) // 20 + "..."
        #expect(result.hasSuffix("..."))
    }

    @Test("Unknown tool returns tool name")
    func unknownTool() {
        let result = ToolSummary.generate(
            toolName: "MyCustomTool",
            toolInput: [:]
        )
        #expect(result == "MyCustomTool")
    }

    @Test("MCP tool shows server:tool format")
    func mcpTool() {
        let result = ToolSummary.generate(
            toolName: "mcp__github__create_issue",
            toolInput: [:]
        )
        #expect(result == "github:create_issue")
    }
}
