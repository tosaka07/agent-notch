import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@MainActor
@Suite("Hook installation coordinator")
struct HookInstallationCoordinatorTests {
    @Test("Constructing the coordinator never installs hooks")
    func constructionHasNoInstallationSideEffect() {
        var installWasCalled = false

        _ = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            install: { _ in installWasCalled = true }
        )

        #expect(!installWasCalled)
    }

    @Test("An explicit production install uses the stable runtime and records consent")
    func productionInstallUsesStableRuntime() {
        var installedRuntime: HookRuntime?
        var consentWasRecorded = false
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            install: { installedRuntime = $0 },
            recordConsent: { consentWasRecorded = true }
        )

        #expect(coordinator.installWithUserConsent() == .installed(.production))
        #expect(installedRuntime == .production)
        #expect(consentWasRecorded)
    }

    @Test("An explicit development install uses the neighboring CLI without an environment flag")
    func developmentInstallUsesNeighboringCLI() {
        let appURL = URL(fileURLWithPath: "/tmp/debug/AgentNotch")
        let expectedCLI = "/tmp/debug/agent-notch"
        var installedRuntime: HookRuntime?
        let coordinator = makeCoordinator(
            distribution: "development",
            executableURL: appURL,
            isExecutable: { $0 == expectedCLI },
            install: { installedRuntime = $0 }
        )

        let expected = HookRuntime.development(executablePath: expectedCLI)
        #expect(coordinator.installWithUserConsent() == .installed(expected))
        #expect(installedRuntime == expected)
    }

    @Test("Development reports a missing app executable")
    func missingAppExecutable() {
        let coordinator = makeCoordinator(
            distribution: nil,
            executableURL: nil
        )

        #expect(
            coordinator.installWithUserConsent()
                == .developmentCLIUnavailable(path: nil)
        )
    }

    @Test("Development reports the expected CLI path when it is unavailable")
    func missingCLIExecutable() {
        let coordinator = makeCoordinator(
            distribution: nil,
            executableURL: URL(fileURLWithPath: "/tmp/debug/AgentNotch"),
            isExecutable: { _ in false }
        )

        #expect(
            coordinator.installWithUserConsent()
                == .developmentCLIUnavailable(path: "/tmp/debug/agent-notch")
        )
    }

    @Test("Installer errors are surfaced and do not record consent")
    func installerError() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "installation failed" }
        }
        var consentWasRecorded = false
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            install: { _ in throw TestError() },
            recordConsent: { consentWasRecorded = true }
        )

        #expect(
            coordinator.installWithUserConsent()
                == .failed(message: "installation failed")
        )
        #expect(!consentWasRecorded)
    }

    @Test("Status checks the resolved runtime without installing")
    func statusUsesResolvedRuntime() {
        var checkedRuntime: HookRuntime?
        var installWasCalled = false
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            install: { _ in installWasCalled = true },
            isInstalled: {
                checkedRuntime = $0
                return true
            }
        )

        #expect(coordinator.status() == .installed)
        #expect(checkedRuntime == .production)
        #expect(!installWasCalled)
    }

    @Test("Installing a single agent writes only that agent and records consent")
    func singleAgentInstall() {
        var installed: [HookAgent] = []
        var consentWasRecorded = false
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            installAgent: { agent, _ in installed.append(agent) },
            recordConsent: { consentWasRecorded = true }
        )

        #expect(coordinator.install(.codex) == .installed(.production))
        #expect(installed == [.codex])
        // Authorizing one agent's file is the same authorization as both: onboarding is finished.
        #expect(consentWasRecorded)
    }

    @Test("A single-agent install reports a missing development helper without writing")
    func singleAgentInstallWithoutHelper() {
        var installed: [HookAgent] = []
        var consentWasRecorded = false
        let coordinator = makeCoordinator(
            distribution: nil,
            executableURL: URL(fileURLWithPath: "/tmp/debug/AgentNotch"),
            isExecutable: { _ in false },
            installAgent: { agent, _ in installed.append(agent) },
            recordConsent: { consentWasRecorded = true }
        )

        #expect(
            coordinator.install(.claudeCode)
                == .developmentCLIUnavailable(path: "/tmp/debug/agent-notch")
        )
        #expect(installed.isEmpty)
        #expect(!consentWasRecorded)
    }

    @Test("A single-agent install failure is surfaced and does not record consent")
    func singleAgentInstallFailure() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "settings.json is read-only" }
        }
        var consentWasRecorded = false
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            installAgent: { _, _ in throw TestError() },
            recordConsent: { consentWasRecorded = true }
        )

        #expect(
            coordinator.install(.codex) == .failed(message: "settings.json is read-only")
        )
        #expect(!consentWasRecorded)
    }

    @Test("A per-agent status check surfaces a read failure instead of reporting not installed")
    func perAgentStatusFailure() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "hooks.json is not JSON" }
        }
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            isAgentInstalled: { _, _ in throw TestError() }
        )

        #expect(coordinator.status(of: .codex) == .failed(message: "hooks.json is not JSON"))
    }

    @Test("Removing a single agent reports success and touches only that agent")
    func singleAgentRemoval() {
        var removed: [HookAgent] = []
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            uninstallAgent: { removed.append($0) }
        )

        #expect(coordinator.uninstall(.claudeCode) == .removed)
        #expect(removed == [.claudeCode])
    }

    @Test("A removal failure is surfaced instead of being reported as removed")
    func singleAgentRemovalFailure() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "file is read-only" }
        }
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            uninstallAgent: { _ in throw TestError() }
        )

        #expect(coordinator.uninstall(.codex) == .failed(message: "file is read-only"))
    }

    @Test("Per-agent status reads that agent alone")
    func perAgentStatus() {
        var checked: [HookAgent] = []
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            isAgentInstalled: { agent, _ in
                checked.append(agent)
                return agent == .claudeCode
            }
        )

        #expect(coordinator.status(of: .claudeCode) == .installed)
        #expect(coordinator.status(of: .codex) == .notInstalled)
        #expect(checked == [.claudeCode, .codex])
    }

    @Test("Codex hooks changed after trust are reported as needing review")
    func modifiedCodexHooksNeedReview() async {
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            isAgentInstalled: { _, _ in true },
            inspectCodexHooks: { command in
                #expect(command == "agent-notch hook --agent codex")
                return .needsReview
            }
        )

        #expect(await coordinator.operationalStatus(of: .codex) == .needsCodexReview)
    }

    @Test("Claude status does not invoke Codex trust inspection")
    func claudeStatusSkipsCodexInspection() async {
        var inspectionWasCalled = false
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            isAgentInstalled: { _, _ in true },
            inspectCodexHooks: { _ in
                inspectionWasCalled = true
                return .needsReview
            }
        )

        #expect(await coordinator.operationalStatus(of: .claudeCode) == .installed)
        #expect(!inspectionWasCalled)
    }

    @Test("Configuration paths are shown with the home directory abbreviated")
    func configurationPathsUseTilde() {
        let coordinator = makeCoordinator(distribution: "production", executableURL: nil)

        #expect(coordinator.configurationPaths(of: .claudeCode) == ["~/.claude/settings.json"])
        // Only hooks.json: Codex's config.toml is no longer written.
        #expect(coordinator.configurationPaths(of: .codex) == ["~/.codex/hooks.json"])
    }

    @Test("Installing Codex also opens the rest of its integration; Claude alone does not touch it")
    func codexInstallEnablesTheIntegration() {
        var writes: [Bool] = []
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            setCodexIntegration: { writes.append($0) }
        )

        #expect(coordinator.install(.claudeCode) == .installed(.production))
        #expect(writes.isEmpty)

        #expect(coordinator.install(.codex) == .installed(.production))
        #expect(writes == [true])
    }

    @Test("Removing Codex closes its whole integration, not just the hook entries")
    func codexRemovalDisablesTheIntegration() {
        var writes: [Bool] = []
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            setCodexIntegration: { writes.append($0) }
        )

        #expect(coordinator.uninstall(.claudeCode) == .removed)
        #expect(writes.isEmpty)

        #expect(coordinator.uninstall(.codex) == .removed)
        #expect(writes == [false])
    }

    @Test("A failed Codex removal leaves the integration flag alone")
    func failedRemovalKeepsTheFlag() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "file is read-only" }
        }
        var writes: [Bool] = []
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            uninstallAgent: { _ in throw TestError() },
            setCodexIntegration: { writes.append($0) }
        )

        #expect(coordinator.uninstall(.codex) == .failed(message: "file is read-only"))
        // The hooks are still there, so claiming the integration is closed would be a lie.
        #expect(writes.isEmpty)
    }

    @Test("Onboarding's all-agents install opens the Codex integration too")
    func allAgentsInstallEnablesCodex() {
        var writes: [Bool] = []
        let coordinator = makeCoordinator(
            distribution: "production",
            executableURL: nil,
            setCodexIntegration: { writes.append($0) }
        )

        #expect(coordinator.installWithUserConsent() == .installed(.production))
        #expect(writes == [true])
    }

    private func makeCoordinator(
        distribution: String?,
        executableURL: URL?,
        isExecutable: @escaping (String) -> Bool = { _ in true },
        install: @escaping (HookRuntime) throws -> Void = { _ in },
        isInstalled: @escaping (HookRuntime) throws -> Bool = { _ in false },
        installAgent: @escaping (HookAgent, HookRuntime) throws -> Void = { _, _ in },
        uninstallAgent: @escaping (HookAgent) throws -> Void = { _ in },
        isAgentInstalled: @escaping (HookAgent, HookRuntime) throws -> Bool = { _, _ in false },
        inspectCodexHooks: @escaping (String) async -> CodexHookTrustState = { _ in .trusted },
        recordConsent: @escaping () -> Void = {},
        setCodexIntegration: @escaping (Bool) -> Void = { _ in }
    ) -> HookInstallationCoordinator {
        HookInstallationCoordinator(
            context: .init(
                distributionChannel: distribution,
                appExecutableURL: executableURL,
                isExecutableFile: isExecutable
            ),
            install: install,
            isInstalled: isInstalled,
            installAgent: installAgent,
            uninstallAgent: uninstallAgent,
            isAgentInstalled: isAgentInstalled,
            inspectCodexHooks: inspectCodexHooks,
            recordConsent: recordConsent,
            setCodexIntegration: setCodexIntegration
        )
    }
}
