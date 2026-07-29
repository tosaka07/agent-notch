import Foundation

/// A side-effect-free representation of an `agent-notch` CLI invocation.
///
/// Parsing lives in Core so command semantics can be tested without launching a
/// subprocess or coupling tests to `exit`.
public enum AgentNotchCommand: Equatable, Sendable {
    case hook(agentType: String)
    case install(runtime: HookRuntime)
    case remove

    public static func parse(
        arguments: [String],
        executablePath: String,
        currentDirectory: URL
    ) -> AgentNotchCommand? {
        let command = arguments.first ?? "hook"

        switch command {
        case "hook":
            var agentType = "claude"
            if let index = arguments.firstIndex(of: "--agent"),
                index + 1 < arguments.count
            {
                agentType = arguments[index + 1]
            }
            return .hook(agentType: agentType)

        case "install":
            if arguments.contains("--development") {
                let path = URL(
                    fileURLWithPath: executablePath,
                    relativeTo: currentDirectory
                ).standardizedFileURL.path
                return .install(runtime: .development(executablePath: path))
            }
            return .install(runtime: .production)

        case "remove":
            return .remove

        default:
            return nil
        }
    }
}
