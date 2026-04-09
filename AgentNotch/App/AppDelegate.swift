import AgentNotchCore
import AppKit
import Defaults
import Network
import SwiftUI

extension Notification.Name {
    static let agentNotchAutoExpand = Notification.Name("agentNotchAutoExpand")
    static let agentNotchSessionCompleted = Notification.Name("agentNotchSessionCompleted")
    static let agentNotchSessionSwept = Notification.Name("agentNotchSessionSwept")
    static let agentNotchClosePanel = Notification.Name("agentNotchClosePanel")
    static let agentNotchSessionResumed = Notification.Name("agentNotchSessionResumed")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    /// displayID → controller. Single entry for followFocus/builtinOnly, multiple for allDisplays.
    private var windowControllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var socketServer: SocketServer?
    private var screenObserver: ScreenObserver?
    private var focusedScreenTracker: FocusedScreenTracker?
    private var cleanupTimer: Timer?
    private var displayModeObservations: [Any] = []
    let sessionManager = SessionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.bootstrap()
        setupStatusItem()
        applyDisplayMode()
        setupScreenObserver()
        observeDisplayModeSetting()
        startSocketServer()
        startSessionCleanupTimer()
        HookInstaller.installIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }

    // MARK: - Notch Overlay

    /// Apply the current display mode setting: teardown everything and rebuild.
    private func applyDisplayMode() {
        // Teardown
        focusedScreenTracker?.stop()
        focusedScreenTracker = nil
        for controller in windowControllers.values { controller.close() }
        windowControllers.removeAll()

        switch Defaults[.displayMode] {
        case .followFocus:
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
                ?? NSScreen.builtin ?? NSScreen.screens[0]
            showNotch(on: screen)
            setupFocusedScreenTracker()

        case .allDisplays:
            for screen in NSScreen.screens {
                showNotch(on: screen)
            }

        case .builtinOnly:
            if let builtin = NSScreen.builtin {
                showNotch(on: builtin)
            } else {
                showNotch(on: NSScreen.screens[0])
            }

        case .specificDisplay:
            let targetUUID = Defaults[.specificDisplayUUID]
            let screen = NSScreen.screens.first { $0.displayUUID == targetUUID }
                ?? NSScreen.builtin ?? NSScreen.screens[0]
            showNotch(on: screen)
        }
    }

    private func showNotch(on screen: NSScreen) {
        let id = screen.displayID
        if windowControllers[id] != nil { return }
        let controller = NotchWindowController(screen: screen)
        let contentView = NotchContentView(
            sessionManager: sessionManager, notchSize: screen.notchSize
        )
        controller.show(contentView: contentView)
        windowControllers[id] = controller
    }

    private func removeNotch(displayID: CGDirectDisplayID) {
        windowControllers[displayID]?.close()
        windowControllers.removeValue(forKey: displayID)
    }

    private func setupScreenObserver() {
        let observer = ScreenObserver()
        observer.onScreenChanged = { [weak self] in
            guard let self else { return }
            self.applyDisplayMode()
        }
        screenObserver = observer
    }

    private func setupFocusedScreenTracker() {
        let tracker = FocusedScreenTracker()
        tracker.onScreenChanged = { [weak self] screen in
            guard let self else { return }
            // In followFocus mode: move to the new screen
            guard Defaults[.displayMode] == .followFocus else { return }
            let newID = screen.displayID
            // Close all others, show on new screen
            for (id, controller) in self.windowControllers where id != newID {
                controller.close()
                self.windowControllers.removeValue(forKey: id)
            }
            self.showNotch(on: screen)
        }
        tracker.start()
        focusedScreenTracker = tracker
    }

    private func observeDisplayModeSetting() {
        let handler: (Any) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.applyDisplayMode()
            }
        }
        displayModeObservations = [
            Defaults.observe(.displayMode) { handler($0) },
            Defaults.observe(.specificDisplayUUID) { handler($0) },
        ]
    }

    // MARK: - Session Cleanup

    private func startSessionCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let timeout = Defaults[.sessionTimeout].rawValue
                let swept = self.sessionManager.sweepStale(timeoutSeconds: timeout)
                for item in swept {
                    let reason: String = switch item.reason {
                    case .directoryDeleted: "ディレクトリ削除"
                    case .timeout: "タイムアウト"
                    }
                    NotificationCenter.default.post(
                        name: .agentNotchSessionSwept,
                        object: item.id,
                        userInfo: [
                            "projectName": item.projectName,
                            "message": "\(item.projectName) を自動削除しました（\(reason)）",
                        ]
                    )
                }
            }
        }
    }

    // MARK: - Socket Server

    private func startSocketServer() {
        let manager = sessionManager
        do {
            let server = try SocketServer { message, _ in
                // Parse off MainActor — pure data processing
                let parsed = EventProcessor.parseMessage(message)
                // Capture needed fields before crossing isolation boundary
                let cwd = message["cwd"] as? String
                let transcriptPath = message["transcript_path"] as? String
                let pid = (message["_pid"] as? NSNumber)?.int32Value
                let tty = message["_tty"] as? String

                // Apply state changes on MainActor
                Task { @MainActor in
                    EventProcessor.apply(parsed.event, agentType: parsed.agentType, manager: manager)
                    EventProcessor.backfillSession(
                        parsed.sessionId, cwd: cwd, transcriptPath: transcriptPath,
                        pid: pid, tty: tty, manager: manager
                    )
                }

                // Never block the agent — respond immediately
                return [String: Any]()
            }
            server.start()
            socketServer = server
        } catch {
            Log.socket.error("Failed to start socket server: \(error)")
        }
    }

    // MARK: - Permission Actions (called from UI)

    func approvePermission(sessionId: String, toolUseId: String) {
        socketServer?.respondToPermission(toolUseId: toolUseId, decision: "allow", reason: nil)
        if let session = sessionManager.session(for: sessionId) {
            session.pendingPermissions.removeAll { $0.toolUseId == toolUseId }
            session.status = .thinking
            sessionManager.notifyChange()
        }
    }

    func denyPermission(sessionId: String, toolUseId: String, reason: String?) {
        socketServer?.respondToPermission(toolUseId: toolUseId, decision: "deny", reason: reason)
        if let session = sessionManager.session(for: sessionId) {
            session.pendingPermissions.removeAll { $0.toolUseId == toolUseId }
            session.status = .thinking
            sessionManager.notifyChange()
        }
    }

    func answerQuestion(sessionId: String, toolUseId: String, answer: String) {
        // AskUserQuestion response format
        socketServer?.respondToPermission(toolUseId: toolUseId, decision: "allow", reason: answer)
        if let session = sessionManager.session(for: sessionId) {
            session.pendingQuestion = nil
            session.status = .thinking
            sessionManager.notifyChange()
        }
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Agent Notch")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Agent Notch", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear All Sessions", action: #selector(clearSessions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel() }

    @objc private func clearSessions() {
        sessionManager.removeAllSessions()
        sessionManager.notifyChange()
    }
}
