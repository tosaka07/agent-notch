import Foundation

/// Catalog of the NotificationCenter names used inside Agent Notch.
///
/// - Used to dispatch in-app side effects: auto-expanding the UI, triggering notification
///   display, delivering hot key presses, and so on.
/// - Communication with external processes (hook / socket) does not go through here;
///   `SocketCoordinator` updates `SessionManager` directly.
extension Notification.Name {
    /// A session has a new request or input, so the notch should expand (object: sessionId).
    static let agentNotchAutoExpand = Notification.Name("agentNotchAutoExpand")
    /// A session finished (object: sessionId, userInfo: projectName/title/branch/message/pid/tty/...).
    static let agentNotchSessionCompleted = Notification.Name("agentNotchSessionCompleted")
    /// A session was removed by the sweep (object: sessionId, userInfo: projectName/message/...).
    static let agentNotchSessionSwept = Notification.Name("agentNotchSessionSwept")
    /// Close the panel.
    static let agentNotchClosePanel = Notification.Name("agentNotchClosePanel")
    /// The user returned to a session (object: sessionId) — clears its notification and glow.
    static let agentNotchSessionResumed = Notification.Name("agentNotchSessionResumed")
}
