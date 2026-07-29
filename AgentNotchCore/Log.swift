import Foundation
import Logging

/// Centralized loggers for Agent Notch.
/// Usage: `Log.panel.info("message")`, `Log.socket.error("failed: \(err)")`
///
/// Outputs to stderr — visible in the terminal when running via `swift build && .build/debug/AgentNotch`.
/// Set `AGENT_NOTCH_LOG=debug` env var to enable debug-level output.
public enum Log {
    /// Call once at app startup to configure log level.
    /// Reads `AGENT_NOTCH_LOG` env var: "debug", "info" (default), "error", "trace".
    public static func bootstrap() {
        let envLevel = ProcessInfo.processInfo.environment["AGENT_NOTCH_LOG"]?.lowercased()
        let level: Logger.Level =
            switch envLevel {
            case "trace": .trace
            case "debug": .debug
            case "info": .info
            case "error": .error
            default: .info
            }
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = level
            return handler
        }
    }
    /// Window panel lifecycle, sizing, mode transitions
    public static let panel = Logger(label: "panel")

    /// Hook events, ClaudeEventParser, session state transitions
    public static let events = Logger(label: "events")

    /// Socket server connections and message handling
    public static let socket = Logger(label: "socket")

    /// Terminal jump: PID/TTY resolution, tmux, app activation
    public static let terminal = Logger(label: "terminal")

    /// Completion notifications, flare, marquee
    public static let notification = Logger(label: "notification")

    /// HotZoneTracker: click detection, hover
    public static let input = Logger(label: "input")

    /// Hook installer, CLI handler
    public static let hooks = Logger(label: "hooks")

    /// Claude / Codex usage fetching and local usage adapters
    public static let usage = Logger(label: "usage")

    /// Versioned local snapshots and other app-owned persistence
    public static let persistence = Logger(label: "persistence")
}
