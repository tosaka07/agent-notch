import AgentNotchCore
import AppKit
import Defaults

/// Application entry point (composition root).
/// A thin layer that assembles the coordinators and starts them in order.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessionManager = SessionManager()

    private lazy var statusBar = StatusBarCoordinator(sessionManager: sessionManager)
    /// Pushed before anything Codex-related starts: it decides whether Codex may be touched at all.
    private lazy var codexAccess = CodexAccessCoordinator()
    private lazy var codexQuestions = CodexQuestionCoordinator(sessionManager: sessionManager)
    private lazy var socket = SocketCoordinator(
        sessionManager: sessionManager,
        codexQuestions: codexQuestions
    )
    private lazy var display = DisplayCoordinator(
        sessionManager: sessionManager,
        permissionActions: socket.permissionActions
    )
    private lazy var sweep = SessionSweepCoordinator(sessionManager: sessionManager)
    private lazy var userStatePersistence = UserStatePersistenceCoordinator(sessionManager: sessionManager)
    private lazy var sessionPersistence = SessionSnapshotPersistenceCoordinator(
        sessionManager: sessionManager
    )
    private lazy var hotKeys = HotKeyCoordinator { [weak self] action in
        self?.display.handleGlobalHotKey(action)
    }
    private var runtimeStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.bootstrap()
        SettingsMigrator.migrateIfNeeded()
        AppLocalization.language = Defaults[.appLanguage]
        statusBar.install()

        if Defaults[.hasCompletedOnboarding] {
            startRuntime()
        } else {
            // Having already read the disclosure and left without installing is a decision, not
            // an unfinished tour: reopen on the stopped screen rather than explaining again.
            let initialStep: OnboardingStep =
                Defaults[.hasReviewedHookConsent] ? .blocked : .welcome
            OnboardingWindowController.shared.show(initialStep: initialStep) { [weak self] in
                self?.startRuntime()
            }
        }
    }

    private func startRuntime() {
        guard !runtimeStarted else { return }
        runtimeStarted = true

        userStatePersistence.start()
        sessionPersistence.start(timeoutSeconds: Defaults[.sessionTimeout].rawValue)
        TerminalInfoResolver.resolveRestoredSessions(manager: sessionManager)
        ClaudeDesktopSessionResolver.resolveRestoredSessions(manager: sessionManager)
        codexAccess.start()
        codexQuestions.start()
        socket.start()
        display.start()
        sweep.start()
        hotKeys.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard runtimeStarted else { return }
        sweep.stop()
        display.stop()
        socket.stop()
        codexQuestions.stop()
        codexAccess.stop()
        sessionPersistence.stop()
        userStatePersistence.stop()
    }
}
