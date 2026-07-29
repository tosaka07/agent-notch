import AgentNotchCore
import Defaults
import SwiftUI

/// One agent's integration with Agent Notch, as a single switch plus the files it touches.
///
/// # One switch, not a status row and two buttons
/// Installed / not installed, Install, Reinstall, Remove were four controls saying one thing. What
/// a user decides here is only "does Agent Notch work with this agent or not", so the row is a
/// label on the left and a switch on the right, and its position *is* the status. A stale
/// installation (new events, or a runtime change between development and production) reads as off
/// under `HookInstaller`'s strict check, so switching it on reinstalls without a separate button.
///
/// # Why the switch covers more than hooks
/// The switch is the whole integration, not the hook file alone. For Codex that includes reading
/// its rollout logs, because the question the switch answers is "may this app touch my agent" —
/// nobody wants to reason about hooks and log reading as two policies. The files underneath say
/// exactly what "touch" means, for anyone who does want to know.
struct AgentHookSettingsSection: View {
    let agent: HookAgent

    private let hookInstallation = HookInstallationCoordinator.shared

    @Default(.claudeCodePermissionPassThrough) private var claudeCodePermissionPassThrough
    @Default(.codexPermissionPassThrough) private var codexPermissionPassThrough
    @State private var status: HookInstallationCoordinator.Status = .notInstalled
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle(isOn: integrationBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n: "Integration")
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(isWorking || isRuntimeUnavailable)

            Toggle(isOn: permissionPassThroughBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n: "Let the agent handle permissions")
                    Text(
                        l10n:
                            "Permission requests bypass Agent Notch and follow the agent’s own approval flow. Questions still appear here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(isWorking || status != .installed)

            // The exact files, read from the installer. A switch that says "on" without naming
            // what it writes to is asking to be taken on faith.
            ForEach(hookInstallation.configurationPaths(of: agent), id: \.self) { path in
                HStack(spacing: 8) {
                    Text(verbatim: path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer(minLength: 8)

                    Button {
                        reveal(path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Show in Finder"))
                    .accessibilityLabel(L("Show \(path) in Finder"))
                }
            }

            if let failure {
                Label {
                    Text(verbatim: failure)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(DSColors.signalError)
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            HStack(spacing: 7) {
                AgentMark(agentType: agent.agentType, size: 11, alignedWithFontSize: 11)
                Text(verbatim: agent.agentType.displayName)
            }
        }
        .onAppear(perform: refreshStatus)
    }

    /// The switch's own state is the installation on disk, so it cannot drift from reality.
    private var integrationBinding: Binding<Bool> {
        Binding(
            get: { status == .installed },
            set: { isOn in isOn ? enable() : disable() }
        )
    }

    private var permissionPassThroughBinding: Binding<Bool> {
        switch agent {
        case .claudeCode:
            $claudeCodePermissionPassThrough
        case .codex:
            $codexPermissionPassThrough
        }
    }

    private var detail: String {
        switch status {
        case .developmentCLIUnavailable:
            return L("The hook helper could not be found. Reinstall Agent Notch and try again.")
        case .failed(let message):
            return message
        case .installed, .notInstalled:
            return agent == .codex
                ? L(
                    "Adds hooks so Codex reports sessions, tools, and questions, and lets Agent Notch read its session logs and usage. Off means neither."
                )
                : L("Adds hooks so Claude Code reports sessions, tools, and approvals.")
        }
    }

    private var isRuntimeUnavailable: Bool {
        if case .developmentCLIUnavailable = status { return true }
        return false
    }

    // MARK: - Actions

    private func refreshStatus() {
        status = hookInstallation.status(of: agent)
    }

    private func enable() {
        isWorking = true
        failure = nil
        Task { @MainActor in
            await Task.yield()
            switch hookInstallation.install(agent) {
            case .installed:
                status = .installed
            case .developmentCLIUnavailable(let path):
                status = .developmentCLIUnavailable(path: path)
            case .failed(let message):
                failure = L("Hook installation failed: \(message)")
                // Read the files back rather than trusting the attempt: a partial write must not
                // leave the switch claiming the integration is on.
                refreshStatus()
            }
            isWorking = false
        }
    }

    private func disable() {
        isWorking = true
        failure = nil
        Task { @MainActor in
            await Task.yield()
            if case .failed(let message) = hookInstallation.uninstall(agent) {
                failure = L("Couldn’t remove the hooks: \(message)")
            }
            refreshStatus()
            isWorking = false
        }
    }

    private func reveal(_ tildePath: String) {
        let path = (tildePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // Nothing to select yet — open the directory it would be created in.
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
