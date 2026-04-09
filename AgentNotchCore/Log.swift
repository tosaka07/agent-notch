import os

/// Centralized loggers for Agent Notch.
/// Usage: `Log.panel.debug("message")`, `Log.socket.error("failed: \(err)")`
///
/// View in Console.app: filter by subsystem "dev.tosaka07.AgentNotch"
public enum Log {
    private static let subsystem = "dev.tosaka07.AgentNotch"

    /// Window panel lifecycle, sizing, ignoresMouseEvents
    public static let panel = Logger(subsystem: subsystem, category: "panel")

    /// Hook events, ClaudeEventParser, session state transitions
    public static let events = Logger(subsystem: subsystem, category: "events")

    /// Socket server connections and message handling
    public static let socket = Logger(subsystem: subsystem, category: "socket")

    /// Terminal jump: PID/TTY resolution, tmux, app activation
    public static let terminal = Logger(subsystem: subsystem, category: "terminal")

    /// Completion notifications, flare, marquee
    public static let notification = Logger(subsystem: subsystem, category: "notification")

    /// HotZoneTracker: click detection, hover
    public static let input = Logger(subsystem: subsystem, category: "input")

    /// Hook installer, CLI handler
    public static let hooks = Logger(subsystem: subsystem, category: "hooks")
}
