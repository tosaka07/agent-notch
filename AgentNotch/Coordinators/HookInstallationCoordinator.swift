import AgentNotchCore
import Defaults
import Foundation

/// Resolves the app's distribution channel and manages explicit, user-authorized installs.
///
/// Nothing calls `install()` during ordinary launch. The onboarding and Settings buttons
/// are the only entry points, so merely opening Agent Notch never edits agent configuration.
@MainActor
final class HookInstallationCoordinator {
    static let shared = HookInstallationCoordinator()

    struct Context {
        let distributionChannel: String?
        let appExecutableURL: URL?
        let isExecutableFile: (String) -> Bool

        static func live() -> Context {
            Context(
                distributionChannel: Bundle.main.object(
                    forInfoDictionaryKey: "AgentNotchDistributionChannel"
                ) as? String,
                appExecutableURL: Bundle.main.executableURL,
                isExecutableFile: FileManager.default.isExecutableFile(atPath:)
            )
        }
    }

    enum InstallationResult: Equatable {
        case installed(HookRuntime)
        case developmentCLIUnavailable(path: String?)
        case failed(message: String)
    }

    enum RemovalResult: Equatable {
        case removed
        case failed(message: String)
    }

    enum Status: Equatable {
        case installed
        case needsCodexReview
        case disabledInCodex
        case notInstalled
        case developmentCLIUnavailable(path: String?)
        case failed(message: String)
    }

    private let context: Context
    private let install: (HookRuntime) throws -> Void
    private let isInstalled: (HookRuntime) throws -> Bool
    private let installAgent: (HookAgent, HookRuntime) throws -> Void
    private let uninstallAgent: (HookAgent) throws -> Void
    private let isAgentInstalled: (HookAgent, HookRuntime) throws -> Bool
    private let inspectCodexHooks: (String) async -> CodexHookTrustState
    private let recordConsent: () -> Void
    /// Stores whether Agent Notch may work with Codex beyond its hook — its log files, its app
    /// server. Written here rather than by the UI so the switch cannot leave the two disagreeing.
    private let setCodexIntegration: (Bool) -> Void

    convenience init() {
        self.init(
            context: .live(),
            install: { runtime in
                try HookInstaller.install(using: runtime)
            },
            isInstalled: { runtime in
                try HookInstaller.isInstalled(using: runtime)
            },
            installAgent: { agent, runtime in
                try HookInstaller.install(agent, using: runtime)
            },
            uninstallAgent: { agent in
                try HookInstaller.uninstall(agent)
            },
            isAgentInstalled: { agent, runtime in
                try HookInstaller.isInstalled(agent, using: runtime)
            },
            inspectCodexHooks: { command in
                await CodexHookTrustClient.shared.inspect(expectedCommand: command)
            },
            recordConsent: {
                Defaults[.hasCompletedOnboarding] = true
            },
            setCodexIntegration: { enabled in
                Defaults[.codexIntegrationEnabled] = enabled
            }
        )
    }

    init(
        context: Context,
        install: @escaping (HookRuntime) throws -> Void,
        isInstalled: @escaping (HookRuntime) throws -> Bool = { _ in false },
        installAgent: @escaping (HookAgent, HookRuntime) throws -> Void = { _, _ in },
        uninstallAgent: @escaping (HookAgent) throws -> Void = { _ in },
        isAgentInstalled: @escaping (HookAgent, HookRuntime) throws -> Bool = { _, _ in false },
        inspectCodexHooks: @escaping (String) async -> CodexHookTrustState = { _ in .trusted },
        recordConsent: @escaping () -> Void = {},
        setCodexIntegration: @escaping (Bool) -> Void = { _ in }
    ) {
        self.context = context
        self.install = install
        self.isInstalled = isInstalled
        self.installAgent = installAgent
        self.uninstallAgent = uninstallAgent
        self.isAgentInstalled = isAgentInstalled
        self.inspectCodexHooks = inspectCodexHooks
        self.recordConsent = recordConsent
        self.setCodexIntegration = setCodexIntegration
    }

    @discardableResult
    func installWithUserConsent() -> InstallationResult {
        guard case .success(let runtime) = resolveRuntime() else {
            let path = unavailableDevelopmentCLIPath
            Log.hooks.error("Development hook CLI is unavailable: \(path ?? "unknown path")")
            return .developmentCLIUnavailable(path: path)
        }

        do {
            try install(runtime)
            setCodexIntegration(true)
            recordConsent()
            return .installed(runtime)
        } catch {
            Log.hooks.error("Hook installation failed: \(error.localizedDescription)")
            return .failed(message: error.localizedDescription)
        }
    }

    /// Installs one agent's hooks after an explicit click in Settings.
    ///
    /// Consent is recorded here too: writing one agent's configuration is the same authorization
    /// as writing both, and a user who installed only Codex has still finished onboarding.
    @discardableResult
    func install(_ agent: HookAgent) -> InstallationResult {
        guard case .success(let runtime) = resolveRuntime() else {
            let path = unavailableDevelopmentCLIPath
            Log.hooks.error("Development hook CLI is unavailable: \(path ?? "unknown path")")
            return .developmentCLIUnavailable(path: path)
        }

        do {
            try installAgent(agent, runtime)
            if agent == .codex { setCodexIntegration(true) }
            recordConsent()
            return .installed(runtime)
        } catch {
            Log.hooks.error(
                "Hook installation failed for \(agent.rawValue): \(error.localizedDescription)"
            )
            return .failed(message: error.localizedDescription)
        }
    }

    /// Removes one agent's hooks. Nothing is uninstalled unless the user asks for it here.
    @discardableResult
    func uninstall(_ agent: HookAgent) -> RemovalResult {
        do {
            try uninstallAgent(agent)
            // Off means Agent Notch stops reading Codex's files and talking to its app server too,
            // not just that the hook entries are gone.
            if agent == .codex { setCodexIntegration(false) }
            return .removed
        } catch {
            Log.hooks.error(
                "Hook removal failed for \(agent.rawValue): \(error.localizedDescription)"
            )
            return .failed(message: error.localizedDescription)
        }
    }

    func status() -> Status {
        guard case .success(let runtime) = resolveRuntime() else {
            return .developmentCLIUnavailable(path: unavailableDevelopmentCLIPath)
        }

        do {
            return try isInstalled(runtime) ? .installed : .notInstalled
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// The state of one agent's hooks, for the per-agent switches in Settings.
    func status(of agent: HookAgent) -> Status {
        guard case .success(let runtime) = resolveRuntime() else {
            return .developmentCLIUnavailable(path: unavailableDevelopmentCLIPath)
        }

        do {
            return try isAgentInstalled(agent, runtime) ? .installed : .notInstalled
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// Whether one agent's installed hooks can actually run.
    ///
    /// Claude Code's file presence is sufficient for the integration contract. Codex adds a
    /// separate trust gate, so its own `hooks/list` metadata is consulted after the file check.
    /// An unavailable inspector does not turn a known installation off; only an explicit Codex
    /// state changes the result.
    func operationalStatus(of agent: HookAgent) async -> Status {
        guard case .success(let runtime) = resolveRuntime() else {
            return .developmentCLIUnavailable(path: unavailableDevelopmentCLIPath)
        }

        do {
            guard try isAgentInstalled(agent, runtime) else {
                return .notInstalled
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }

        guard agent == .codex else { return .installed }
        let command = HookInstaller.hookCommand(for: .codex, using: runtime)
        switch await inspectCodexHooks(command) {
        case .trusted:
            return .installed
        case .needsReview:
            return .needsCodexReview
        case .disabled:
            return .disabledInCodex
        case .notFound, .unavailable:
            return .installed
        }
    }

    /// The configuration files this agent's hooks are written to, with `~` for the home directory.
    func configurationPaths(of agent: HookAgent) -> [String] {
        HookInstaller.installationTargets(for: agent)
            .map { ($0 as NSString).abbreviatingWithTildeInPath }
    }

    private var unavailableDevelopmentCLIPath: String? {
        guard context.distributionChannel != "production",
            let appExecutableURL = context.appExecutableURL
        else { return nil }
        return
            appExecutableURL
            .deletingLastPathComponent()
            .appendingPathComponent("agent-notch")
            .path
    }

    private func resolveRuntime() -> Result<HookRuntime, RuntimeResolutionError> {
        if context.distributionChannel == "production" {
            return .success(.production)
        }

        guard let cliPath = unavailableDevelopmentCLIPath,
            context.isExecutableFile(cliPath)
        else {
            return .failure(.developmentCLIUnavailable)
        }
        return .success(.development(executablePath: cliPath))
    }

    private enum RuntimeResolutionError: Error {
        case developmentCLIUnavailable
    }
}
