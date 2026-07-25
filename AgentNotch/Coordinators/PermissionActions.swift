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
    /// AskUserQuestion への応答。`answers` は `{question: [選ばれたラベル]}` の map。
    /// multiSelect でも single でも配列で渡し、single は要素 1 の配列にする。
    var answerQuestion: @MainActor (_ sessionId: String, _ toolUseId: String, _ answers: [String: [String]]) -> Void = { _, _, _ in }
    /// 失効した質問/権限バナーをユーザー操作で閉じる（応答は送らない）。
    var dismissExpired: @MainActor (_ sessionId: String, _ toolUseId: String) -> Void = { _, _ in }
}

extension EnvironmentValues {
    @Entry var permissionActions: PermissionActions = PermissionActions()
}
