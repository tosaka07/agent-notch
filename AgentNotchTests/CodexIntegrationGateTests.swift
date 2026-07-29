import AgentNotchCore
import Defaults
import Foundation
import Testing

@testable import AgentNotch

/// The Codex switch has to stop the adapters that reach out to Codex, not just the hook file.
///
/// Gating only the rollout monitor left `codex app-server` being spawned and the Desktop IPC client
/// connecting while Settings said the integration was off. These tests pin all three to the setting,
/// and pin the flag itself to the hooks actually on disk.
///
/// `Defaults` and `CodexAccess` are process-wide, so the suite is serialized and every test restores
/// what it changed.
@Suite("Codex integration gate", .serialized)
@MainActor
struct CodexIntegrationGateTests {
    // MARK: - Adapters

    private final class SpyTransport: CodexSharedQuestionTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var starts = 0
        private var stops = 0

        var startCount: Int { lock.withLock { starts } }
        var stopCount: Int { lock.withLock { stops } }

        func start() { lock.withLock { starts += 1 } }
        func stop() { lock.withLock { stops += 1 } }
        func setFollowedThreadIds(_ ids: Set<String>) {}
        func submit(requestId: CodexRPCID, answers: [String: [String]]) async throws {}
    }

    private final class SpyDesktopTransport: CodexDesktopQuestionTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var stops = 0

        var stopCount: Int { lock.withLock { stops } }

        func start() {}
        func stop() { lock.withLock { stops += 1 } }
        func setFollowedThreadIds(_ ids: Set<String>) {}
        func submit(
            threadId: String,
            requestId: CodexRPCID,
            answers: [String: [String]]
        ) async throws {}
    }

    private final class SpyMonitor: CodexRolloutQuestionMonitoring {
        var startCount = 0
        var stopCount = 0
        var watched: [String: String] = [:]

        func start() { startCount += 1 }
        func stop() { stopCount += 1 }
        func setWatchedSessions(_ transcriptPathBySessionId: [String: String]) {
            watched = transcriptPathBySessionId
        }
    }

    // MARK: - CodexQuestionCoordinator

    @Test("With the integration off, no adapter is started")
    func adaptersStayDownWhileOff() {
        withIntegration(false) {
            let shared = SpyTransport()
            let monitor = SpyMonitor()
            let coordinator = CodexQuestionCoordinator(
                sessionManager: SessionManager(),
                sharedTransport: shared,
                desktopTransport: SpyDesktopTransport(),
                rolloutMonitor: monitor
            )

            coordinator.start()
            defer { coordinator.stop() }

            // Not one of the three: the app server is not spawned and no rollout file is opened.
            #expect(shared.startCount == 0)
            #expect(monitor.startCount == 0)
        }
    }

    @Test("With the integration on, the transport and the rollout monitor both run")
    func adaptersRunWhileOn() {
        withIntegration(true) {
            let shared = SpyTransport()
            let monitor = SpyMonitor()
            let coordinator = CodexQuestionCoordinator(
                sessionManager: SessionManager(),
                sharedTransport: shared,
                desktopTransport: SpyDesktopTransport(),
                rolloutMonitor: monitor
            )

            coordinator.start()
            defer { coordinator.stop() }

            #expect(shared.startCount == 1)
            #expect(monitor.startCount == 1)
        }
    }

    @Test("Turning the setting off while running stops every adapter")
    func turningOffStopsAdapters() async {
        Defaults[.codexIntegrationEnabled] = true
        defer { Defaults[.codexIntegrationEnabled] = true }

        let shared = SpyTransport()
        let desktop = SpyDesktopTransport()
        let monitor = SpyMonitor()
        let coordinator = CodexQuestionCoordinator(
            sessionManager: SessionManager(),
            sharedTransport: shared,
            desktopTransport: desktop,
            rolloutMonitor: monitor
        )
        coordinator.start()
        defer { coordinator.stop() }
        #expect(shared.startCount == 1)

        Defaults[.codexIntegrationEnabled] = false
        // The observation hops to the MainActor, so wait for it rather than assuming.
        for _ in 0..<40 where monitor.stopCount == 0 {
            try? await Task.sleep(for: .milliseconds(25))
        }

        #expect(monitor.stopCount >= 1)
        #expect(shared.stopCount >= 1)
        #expect(desktop.stopCount >= 1)
    }

    // MARK: - CodexAccessCoordinator

    @Test("The stored flag is reconciled from the hooks on disk, and pushed into Core")
    func flagFollowsTheInstalledHooks() {
        Defaults[.codexIntegrationEnabled] = true
        defer {
            Defaults[.codexIntegrationEnabled] = true
            CodexAccess.setAllowed(true)
        }

        // Hooks gone (removed by hand, say): the integration must not keep reading Codex files.
        let uninstalled = CodexAccessCoordinator(
            hookInstallation: makeHookCoordinator(codexInstalled: false))
        uninstalled.start()
        defer { uninstalled.stop() }

        #expect(!Defaults[.codexIntegrationEnabled])
        #expect(!CodexAccess.isAllowed)

        let installed = CodexAccessCoordinator(
            hookInstallation: makeHookCoordinator(codexInstalled: true))
        installed.start()
        defer { installed.stop() }

        #expect(Defaults[.codexIntegrationEnabled])
        #expect(CodexAccess.isAllowed)
    }

    @Test("A hook file that cannot be read leaves the setting alone")
    func unreadableHooksDoNotDisableTheIntegration() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "hooks.json is not JSON" }
        }
        Defaults[.codexIntegrationEnabled] = true
        defer {
            Defaults[.codexIntegrationEnabled] = true
            CodexAccess.setAllowed(true)
        }

        let coordinator = CodexAccessCoordinator(
            hookInstallation: HookInstallationCoordinator(
                context: .init(
                    distributionChannel: "production",
                    appExecutableURL: nil,
                    isExecutableFile: { _ in true }
                ),
                install: { _ in },
                isAgentInstalled: { _, _ in throw TestError() }
            )
        )
        coordinator.start()
        defer { coordinator.stop() }

        // A momentarily unreadable file is not consent to turn the integration off.
        #expect(Defaults[.codexIntegrationEnabled])
        #expect(CodexAccess.isAllowed)
    }

    // MARK: - Helpers

    private func withIntegration(_ enabled: Bool, _ body: () -> Void) {
        Defaults[.codexIntegrationEnabled] = enabled
        defer { Defaults[.codexIntegrationEnabled] = true }
        body()
    }

    private func makeHookCoordinator(codexInstalled: Bool) -> HookInstallationCoordinator {
        HookInstallationCoordinator(
            context: .init(
                distributionChannel: "production",
                appExecutableURL: nil,
                isExecutableFile: { _ in true }
            ),
            install: { _ in },
            isAgentInstalled: { agent, _ in agent == .codex ? codexInstalled : true }
        )
    }
}
