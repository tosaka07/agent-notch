import Foundation
import SwiftUI

/// Factory that builds a `NotchNotificationManager.Item` from the userInfo of
/// `agentNotchSessionCompleted` / `agentNotchSessionSwept`.
@MainActor
enum SessionNotificationBuilder {
    /// Completion notification.
    static func completionItem(
        sessionId: String,
        userInfo: [AnyHashable: Any],
        onTap: (() -> Void)? = nil
    ) -> NotchNotificationManager.Item {
        let projectName = userInfo["projectName"] as? String ?? L("Session")
        let sessionTitle = userInfo["sessionTitle"] as? String
        let gitBranch = userInfo["gitBranch"] as? String
        let isWT = userInfo["isWorktree"] as? Bool ?? false
        let msg = sanitizedMessage(userInfo["message"] as? String ?? "")

        let content = AnyView(
            SessionNotificationContent(
                icon: AnyView(Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)),
                sessionTitle: sessionTitle,
                projectName: projectName,
                gitBranch: gitBranch,
                isWorktree: isWT,
                message: msg
            )
        )
        return NotchNotificationManager.Item(
            id: sessionId,
            content: content,
            autoDismissAfter: 10,
            createdAt: Date(),
            onTap: onTap
        )
    }

    /// Sweep notification.
    static func sweptItem(
        sessionId: String,
        userInfo: [AnyHashable: Any]
    ) -> NotchNotificationManager.Item {
        let projectName = userInfo["projectName"] as? String ?? L("Session")
        let msg = userInfo["message"] as? String ?? ""

        let content = AnyView(
            SessionNotificationContent(
                icon: AnyView(Image(systemName: "trash.circle.fill").foregroundStyle(.orange)),
                projectName: projectName,
                gitBranch: nil,
                message: msg
            )
        )
        return NotchNotificationManager.Item(
            id: "swept-\(sessionId)",
            content: content,
            autoDismissAfter: 10,
            createdAt: Date()
        )
    }

    private static func sanitizedMessage(_ message: String) -> String {
        let text =
            message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if text.count > 100 {
            return String(text.prefix(100)) + "..."
        }
        return text
    }
}
