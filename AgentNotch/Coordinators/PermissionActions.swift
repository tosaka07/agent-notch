import SwiftUI

/// Injection point for permission operations (approve / deny / terminal handoff / answerQuestion).
/// `SocketCoordinator` supplies the concrete closures and hands them to views
/// through `EnvironmentValues`.
///
/// Usage:
/// ```swift
/// @Environment(\.permissionActions) private var actions
/// actions.approve(sessionId, toolUseId)
/// ```
struct PermissionActions: Sendable {
    var approve: @MainActor (_ sessionId: String, _ toolUseId: String) -> Void = { _, _ in }
    var deny: @MainActor (_ sessionId: String, _ toolUseId: String, _ reason: String?) -> Void = { _, _, _ in
    }
    /// Releases a PermissionRequest without deciding it, so the agent shows its terminal prompt.
    var respondInTerminal: @MainActor (_ sessionId: String, _ toolUseId: String) -> Void = { _, _ in }
    /// Answers an AskUserQuestion. `answers` maps `{question: [selected labels]}`.
    /// Always an array, for both multiSelect and single; single uses a one-element array.
    var answerQuestion:
        @MainActor (_ sessionId: String, _ toolUseId: String, _ answers: [String: [String]]) -> Void = {
            _, _, _ in
        }
    /// Dismisses an expired question/permission banner by user action (sends no response).
    var dismissExpired: @MainActor (_ sessionId: String, _ toolUseId: String) -> Void = { _, _ in }
}

extension EnvironmentValues {
    @Entry var permissionActions: PermissionActions = PermissionActions()
}
