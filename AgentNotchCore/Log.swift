import Logging

/// Centralized loggers for Agent Notch.
/// Usage: `Log.panel.info("message")`, `Log.socket.error("failed: \(err)")`
///
/// Outputs to stdout — visible in the terminal when running via `swift build && .build/debug/AgentNotch`.
public enum Log {
    /// Window panel lifecycle, sizing, ignoresMouseEvents
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
}
