import AgentNotchCore
import Defaults
import Foundation

/// Keeps `CodexAccess` — Core's one gate on touching Codex — in step with the user's setting.
///
/// Core cannot read `Defaults` (it does not depend on it) and must not guess, so the app pushes the
/// value in: once at launch and again whenever the setting changes.
///
/// # Reconciling at launch
/// The Settings switch writes both the hooks on disk and the stored flag, so they normally agree.
/// They can still drift — a hooks file edited by hand, or an install from a different build of the
/// app. The hooks are the observable truth (they are what makes Codex call us), so at launch the
/// flag is brought in line with them. Without that, a hooks file someone removed by hand would
/// leave Agent Notch still reading rollout files and spawning `codex app-server`.
@MainActor
final class CodexAccessCoordinator {
    private let hookInstallation: HookInstallationCoordinator
    private var observation: Defaults.Observation?

    init(hookInstallation: HookInstallationCoordinator = .shared) {
        self.hookInstallation = hookInstallation
    }

    func start() {
        reconcileWithInstalledHooks()
        apply()
        observation = Defaults.observe(.codexIntegrationEnabled) { [weak self] _ in
            Task { @MainActor in
                self?.apply()
            }
        }
    }

    func stop() {
        observation = nil
    }

    /// Brings the stored flag in line with whether Codex's hooks are actually installed.
    ///
    /// A failure to read the hook files is not treated as "off": that would silently disable the
    /// integration because a file was momentarily unreadable. Only a definite "not installed"
    /// turns it off.
    private func reconcileWithInstalledHooks() {
        switch hookInstallation.status(of: .codex) {
        case .installed:
            Defaults[.codexIntegrationEnabled] = true
        case .notInstalled:
            Defaults[.codexIntegrationEnabled] = false
        case .developmentCLIUnavailable, .failed:
            break
        }
    }

    private func apply() {
        let enabled = Defaults[.codexIntegrationEnabled]
        CodexAccess.setAllowed(enabled)
        Log.hooks.info("Codex integration \(enabled ? "enabled" : "disabled")")
    }
}
