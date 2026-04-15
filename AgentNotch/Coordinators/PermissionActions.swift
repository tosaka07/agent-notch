import SwiftUI

/// Permission 操作 (approve / deny / answerQuestion) の注入用 struct。
/// SocketCoordinator が具体的な実装クロージャを用意し、EnvironmentValues 経由で View に流す。
///
/// 利用側:
/// ```swift
/// @Environment(\.permissionActions) private var actions
/// actions.approve(sessionId, toolUseId)
/// ```
struct PermissionActions: Sendable {
    var approve: @MainActor (_ sessionId: String, _ toolUseId: String) -> Void = { _, _ in }
    var deny: @MainActor (_ sessionId: String, _ toolUseId: String, _ reason: String?) -> Void = { _, _, _ in }
    var answerQuestion: @MainActor (_ sessionId: String, _ toolUseId: String, _ answer: String) -> Void = { _, _, _ in }
}

extension EnvironmentValues {
    @Entry var permissionActions: PermissionActions = PermissionActions()
}
