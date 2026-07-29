import AgentNotchCore
import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

/// Native macOS sidebar/content composition for the settings window.
///
/// `NavigationSplitView` lets macOS place the traffic lights in the sidebar
/// title-bar area and supply the standard source-list material and section
/// headings. Only the row content is customized to match the app icon language.
struct SettingsSplitView: View {
    @Bindable var selection: SettingsSelection
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.tab) {
                sidebarRow(.general)

                ForEach(SettingsSidebarSection.allCases) { section in
                    Section(section.title) {
                        ForEach(section.tabs) { tab in
                            sidebarRow(tab)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Agent Notch")
            .navigationSplitViewColumnWidth(
                min: SettingsWindowSizing.minimumSidebarWidth,
                ideal: SettingsWindowSizing.sidebarWidth,
                max: SettingsWindowSizing.maximumSidebarWidth
            )
        } detail: {
            SettingsView(
                selection: selection,
                sessionManager: sessionManager
            )
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.locale, AppLocalization.language.locale)
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        HStack(spacing: 7) {
            SettingsSidebarIcon(tab: tab)
            Text(tab.title)
                .font(.system(size: 12.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .listRowInsets(
            EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        )
        .tag(tab)
    }
}

private struct SettingsSidebarIcon: View {
    let tab: SettingsTab

    var body: some View {
        Image(systemName: tab.symbolName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                LinearGradient(
                    colors: [
                        tab.iconColor.color.mix(with: .white, by: 0.16),
                        tab.iconColor.color.mix(with: .black, by: 0.10),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(
                color: .black.opacity(0.28),
                radius: 1.25,
                y: 0.75
            )
    }
}

extension SettingsTab.IconColor {
    fileprivate var color: Color {
        switch self {
        case .gray: .gray
        case .blue: .blue
        case .orange: .orange
        case .red: .red
        case .green: .green
        case .purple: .purple
        case .indigo: .indigo
        }
    }
}

/// Contents of the settings window.
///
/// Switching destinations belongs to the native SwiftUI sidebar
/// (`SettingsWindowController`); this only presents the selected pane's `Form`.
/// **One `Form` per destination**, so every pane scrolls independently inside
/// the settings window's fixed-height content area.
struct SettingsView: View {
    @Bindable var selection: SettingsSelection
    @ObservedObject var sessionManager: SessionManager

    /// Preferred width of the content pane, excluding the sidebar.
    static let contentWidth: CGFloat = 720
    static let minimumContentWidth: CGFloat = 560

    var body: some View {
        Group {
            switch selection.tab {
            case .general: GeneralSettings()
            case .sessions: SessionSettings(sessionManager: sessionManager)
            case .hooks: HookSettings()
            case .notifications: NotificationSettings()
            case .usage: UsageSettings()
            case .glyphs: GlyphGuideSettings()
            case .shortcuts: ShortcutSettings()
            case .about: AboutSettings()
            }
        }
        .formStyle(.grouped)
        .frame(
            minWidth: Self.minimumContentWidth,
            idealWidth: Self.contentWidth,
            maxWidth: .infinity
        )
        // Dynamic rows can outgrow the available screen height; keep each Form scrollable.
        .environment(\.locale, AppLocalization.language.locale)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Default(.appLanguage) var appLanguage
    @Default(.textSize) var textSize
    @Default(.displayMode) var displayMode
    @Default(.specificDisplayUUID) var specificDisplayUUID
    @Default(.cardPromptSource) var cardPromptSource
    @Default(.sessionTimeout) var sessionTimeout
    @State private var isShowingLanguageRestartConfirmation = false
    @State private var isShowingRestartFailure = false

    var body: some View {
        Form {
            Section(L("Appearance")) {
                Picker(L("Language"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
                .onChange(of: appLanguage) { _, language in
                    isShowingLanguageRestartConfirmation =
                        language != AppLocalization.language
                }
                if appLanguage != AppLocalization.language {
                    Text(l10n: "Language changes take effect after restarting Agent Notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker(L("Text size"), selection: $textSize) {
                    ForEach(TextSizePreference.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(l10n: "Preview:")
                        .foregroundStyle(.secondary)
                    Text(l10n: "Aa Sample Preview 123")
                        .font(.system(size: 11 * textSize.scale))
                }

                Picker(L("Display"), selection: $displayMode) {
                    ForEach(DisplayModePreference.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if displayMode == .specificDisplay {
                    Picker(L("Target display"), selection: $specificDisplayUUID) {
                        ForEach(availableDisplays, id: \.uuid) { display in
                            HStack(spacing: 6) {
                                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                                    .font(.system(size: 10))
                                Text(display.name)
                            }
                            .tag(display.uuid)
                        }
                    }
                }
            }

            // Two one-off actions that belong to no setting above. A section each
            // would spend a whole row on a single button, so they share one.
            Section {
                HStack {
                    Button(L("Show Onboarding")) {
                        // Nothing to run on completion — the runtime is already up, so
                        // finishing the tour just closes its window.
                        OnboardingWindowController.shared.show {}
                    }
                    Button(L("Quit Agent Notch")) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .onAppear {
            // Preselect the first display when no target has been chosen yet.
            if displayMode == .specificDisplay, specificDisplayUUID.isEmpty,
                let first = availableDisplays.first
            {
                specificDisplayUUID = first.uuid
            }
        }
        .confirmationDialog(
            L("Restart Agent Notch?"),
            isPresented: $isShowingLanguageRestartConfirmation
        ) {
            Button(L("Restart Now")) {
                AppRelauncher.relaunch(onFailure: {
                    isShowingRestartFailure = true
                })
            }
            Button(L("Later"), role: .cancel) {}
        } message: {
            Text(l10n: "Restart Agent Notch to use the selected language.")
        }
        .alert(
            L("Couldn’t restart Agent Notch."),
            isPresented: $isShowingRestartFailure
        ) {
            Button(L("OK")) {}
        } message: {
            Text(
                l10n:
                    "Quit Agent Notch and open it again to use the selected language."
            )
        }
    }

    private struct DisplayInfo: Identifiable {
        let uuid: String
        let name: String
        let isBuiltin: Bool
        var id: String { uuid }
    }

    private var availableDisplays: [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            return DisplayInfo(
                uuid: uuid,
                name: screen.displayName,
                isBuiltin: screen.isBuiltinDisplay
            )
        }
    }
}

// MARK: - Sessions

private struct SessionSettings: View {
    @ObservedObject var sessionManager: SessionManager
    @Default(.cardPromptSource) var cardPromptSource
    @Default(.sessionTimeout) var sessionTimeout
    @State private var isShowingRemoveAllConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker(L("Title fallback"), selection: $cardPromptSource) {
                    ForEach(CardPromptSource.allCases, id: \.self) { source in
                        Text(source.label).tag(source)
                    }
                }
                Text(l10n: "Used when the agent does not provide a session title.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(L("Auto-remove"), selection: $sessionTimeout) {
                    ForEach(SessionTimeoutPreference.allCases, id: \.self) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                Text(
                    l10n:
                        "Removes idle sessions once the chosen time has passed since their last activity.\nSessions whose directory has been deleted are removed immediately."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(L("Session data")) {
                Button(L("Remove all sessions"), role: .destructive) {
                    isShowingRemoveAllConfirmation = true
                }
                .disabled(sessionManager.allSessions.isEmpty)

                Text(
                    l10n:
                        "Removes every session from Agent Notch. This action cannot be undone."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            L("Remove all sessions?"),
            isPresented: $isShowingRemoveAllConfirmation
        ) {
            Button(L("Remove all sessions"), role: .destructive) {
                sessionManager.removeAllSessions()
                sessionManager.notifyChange()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(l10n: "This action cannot be undone.")
        }
    }
}

// MARK: - Hooks

/// Hook installation is the one pane that explains what the app writes outside
/// its own container, so it gets its own tab rather than sitting at the bottom
/// of General where it was the longest section by far.
private struct HookSettings: View {
    var body: some View {
        Form {
            ForEach(HookAgent.allCases, id: \.self) { agent in
                AgentHookSettingsSection(agent: agent)
            }
        }
    }
}

// MARK: - Notifications

private struct NotificationSettings: View {
    @Default(.notificationTapAction) var notificationTapAction
    @Default(.soundEnabled) var soundEnabled
    @Default(.soundCompleted) var soundCompleted
    @Default(.soundSubagentCompleted) var soundSubagentCompleted
    @Default(.soundPermission) var soundPermission
    @Default(.soundQuestion) var soundQuestion
    @Default(.soundError) var soundError

    var body: some View {
        Form {
            Section {
                Picker(L("On tap"), selection: $notificationTapAction) {
                    ForEach(NotificationTapAction.allCases, id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }
            }

            Section(L("Sound")) {
                Toggle(L("Enable sound"), isOn: $soundEnabled)

                if soundEnabled {
                    SoundPickerView(event: .sessionCompleted, choice: $soundCompleted)
                    SoundPickerView(event: .subagentCompleted, choice: $soundSubagentCompleted)
                    SoundPickerView(event: .permissionWaiting, choice: $soundPermission)
                    SoundPickerView(event: .question, choice: $soundQuestion)
                    SoundPickerView(event: .error, choice: $soundError)
                }
            }
        }
    }
}

// MARK: - Usage

private struct UsageSettings: View {
    @Default(.usageEnabled) var usageEnabled
    @Default(.usageGaugeStyle) var usageGaugeStyle
    @Default(.usageGaugeMetric) var usageGaugeMetric

    var body: some View {
        Form {
            Section {
                Toggle(L("Show usage"), isOn: $usageEnabled)
                Text(
                    l10n:
                        "Shows how much of Claude's and Codex's rate limits you have consumed, on the left of the session list's top bar.\nClicking a gauge opens the full breakdown.\nWhen off, neither your credentials nor the API are touched."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if usageEnabled {
                    Picker(L("Gauge style"), selection: $usageGaugeStyle) {
                        ForEach(UsageGaugeStyle.allCases, id: \.self) { style in
                            Text(style.label).tag(style)
                        }
                    }

                    Picker(L("Window shown in the gauge"), selection: $usageGaugeMetric) {
                        ForEach(UsageGaugeMetric.allCases, id: \.self) { metric in
                            Text(metric.label).tag(metric)
                        }
                    }
                    Text(
                        l10n:
                            "Only one gauge is shown per agent.\nAgents that lack the chosen window — Codex has no per-model window, for instance — fall back to automatic.\nThe full breakdown is on the usage page."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(L("Focus Agent Notch"), name: .jumpToNotification)
                KeyboardShortcuts.Recorder(L("Jump to terminal"), name: .jumpToTerminal)
                KeyboardShortcuts.Recorder(L("Approve permission"), name: .approvePermission)
                KeyboardShortcuts.Recorder(L("Deny permission"), name: .denyPermission)
                Text(
                    l10n:
                        "Approve and deny work even while the app is inactive.\nThe notch panel cannot receive keyboard input until it is clicked, so a banner's ⏎ / esc only work after clicking the panel."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button(L("Reset to defaults")) {
                    KeyboardShortcuts.reset(
                        .jumpToNotification, .jumpToTerminal, .approvePermission, .denyPermission
                    )
                }
                .font(.caption)
            }
        }
    }
}
