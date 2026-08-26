import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Session sweep coordinator", .serialized)
@MainActor
struct SessionSweepCoordinatorTests {
    @Test("A removed session is published with its user-facing reason")
    func removedSessionPublishesNotification() async throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "missing-directory", agentType: .codex)
        session.cwd = "/tmp/agent-notch-missing-\(UUID().uuidString)"
        session.gitInfo = GitInfo(
            branch: nil,
            originRepoName: "Deleted Project",
            worktreeName: nil
        )

        let notificationCenter = NotificationCenter()
        let received = NotificationBox()
        let observer = notificationCenter.addObserver(
            forName: .agentNotchSessionSwept,
            object: nil,
            queue: nil
        ) { notification in
            received.value = notification
        }
        defer { notificationCenter.removeObserver(observer) }

        let coordinator = SessionSweepCoordinator(
            sessionManager: manager,
            interval: 0.01,
            timeoutSeconds: { 3_600 },
            notificationCenter: notificationCenter
        )
        coordinator.start()
        defer { coordinator.stop() }

        try await waitUntil { manager.session(for: "missing-directory") == nil }

        let notification = try #require(received.value)
        #expect(notification.object as? String == "missing-directory")
        #expect(notification.userInfo?["projectName"] as? String == "Deleted Project")
        #expect(
            notification.userInfo?["message"] as? String
                == "Removed Deleted Project automatically (Directory deleted)"
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    private final class NotificationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue: Notification?

        var value: Notification? {
            get { lock.withLock { storedValue } }
            set { lock.withLock { storedValue = newValue } }
        }
    }
}
