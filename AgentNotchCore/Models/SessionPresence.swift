import Foundation

/// How confidently Agent Notch knows that a session is attached to a live runtime.
///
/// `SessionStatus` describes what the agent is doing. Presence is deliberately separate:
/// after Agent Notch relaunches, the persisted status is only a last-known value until a
/// fresh hook event arrives.
public enum SessionPresence: String, Codable, Sendable {
    /// At least one hook event from the currently attached runtime arrived in this app process.
    case live
    /// Restored from disk. The process may still exist, but no fresh event has confirmed it yet.
    case restored
    /// The attached process is known to have exited.
    case inactive
}
