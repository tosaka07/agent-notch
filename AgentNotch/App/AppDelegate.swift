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
            let server = try SocketServer { message, connection in
                let event = ClaudeEventParser.parse(message)
                let sessionId = message["session_id"] as? String ?? ""
                // Detect agent type from _agent_type field injected by CLI
                let agentType: AgentType = (message["_agent_type"] as? String) == "codex" ? .codex : .claudeCode

                // All events respond immediately — never block Claude Code.
                // PermissionRequest/AskQuestion update the UI but don't hold the connection.
                let isDeferred = false

                // Extract common fields available on all hook events
                let cwd = message["cwd"] as? String
                let transcriptPath = message["transcript_path"] as? String
                let pid = (message["_pid"] as? NSNumber)?.int32Value
                let tty = message["_tty"] as? String

                Task { @MainActor in
                    AppDelegate.processEvent(event, agentType: agentType, manager: manager)
                    // Backfill fields on every event (may have been missing on auto-created sessions)
                    if let session = manager.session(for: sessionId) {
                        session.lastActivityAt = Date()
                        if session.cwd == nil, let cwd { session.cwd = cwd }
                        if session.transcriptPath == nil, let transcriptPath { session.transcriptPath = transcriptPath }
                        if session.pid == nil, let pid { session.pid = pid }
                        if session.tty == nil, let tty { session.tty = tty }
                    }
                }

                return isDeferred ? nil : [String: Any]()
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

    // MARK: - Event Processing

    @MainActor
    static func processEvent(_ event: ClaudeEvent, agentType: AgentType = .claudeCode, manager: SessionManager) {
        defer { manager.notifyChange() }

        switch event {
        case let .sessionStarted(info):
            Log.events.info("sessionStarted id=\(info.sessionId) model=\(info.model ?? "?") cwd=\(info.cwd ?? "?")")
            let session = manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
            session.model = info.model
            session.cwd = info.cwd
            session.transcriptPath = info.transcriptPath
            session.status = .idle

        case let .userPrompt(sessionId):
            Log.events.info("userPrompt id=\(sessionId)")
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
            session.status = .thinking
            NotificationCenter.default.post(name: .agentNotchSessionResumed, object: sessionId)

        case let .toolStarted(info):
            let session = manager.session(for: info.sessionId)
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
            session.status = .toolRunning
            session.currentTool = ToolInfo(
                id: info.toolUseId, name: info.toolName, summary: info.summary,
                input: info.toolInput, startedAt: Date(), status: .running
            )
            session.toolCallCount += 1

        case let .toolCompleted(info):
            if let session = manager.session(for: info.sessionId) {
                if var tool = session.currentTool, tool.id == info.toolUseId {
                    tool.status = .succeeded
                    tool.completedAt = Date()
                    session.recentTools.insert(tool, at: 0)
                    if session.recentTools.count > 50 { session.recentTools.removeLast() }
                }
                session.currentTool = nil
                session.status = .thinking
            }

        case let .toolFailed(info):
            if let session = manager.session(for: info.sessionId) {
                if var tool = session.currentTool, tool.id == info.toolUseId {
                    tool.status = .failed; tool.completedAt = Date()
                    session.recentTools.insert(tool, at: 0)
                    if session.recentTools.count > 50 { session.recentTools.removeLast() }
                }
                session.currentTool = nil
                session.status = .thinking
            }

        case let .permissionRequested(info):
            let session = manager.session(for: info.sessionId)
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
            session.status = .permissionWaiting
            session.pendingPermissions.append(PermissionRequest(
                id: UUID().uuidString, agentType: .claudeCode,
                sessionId: info.sessionId, toolName: info.toolName,
                toolInput: info.toolInput, toolUseId: info.toolUseId,
                timestamp: Date(), canRespond: true
            ))
            // Auto-expand notch
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)

        case let .askQuestion(info):
            let session = manager.session(for: info.sessionId)
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
            session.status = .permissionWaiting
            session.pendingQuestion = PendingQuestion(
                toolUseId: info.toolUseId, question: info.question, options: info.options
            )
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)

        case let .notification(sessionId, type, _):
            if type == "idle_prompt" {
                let session = manager.session(for: sessionId)
                    ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
                session.status = .idle
            }

        case let .subagentStarted(sessionId, _):
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
            session.status = .subagentRunning

        case let .stopFailure(sessionId, errorType):
            Log.events.error("stopFailure id=\(sessionId) error=\(errorType)")
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
            session.status = .error
            session.currentTool = nil

        case let .compactingDone(sessionId):
            if let session = manager.session(for: sessionId) {
                session.status = .thinking
            }

        case let .sessionIdle(sessionId):
            Log.events.info("sessionIdle (done) id=\(sessionId)")
            if let session = manager.session(for: sessionId) {
                session.status = .done
                session.currentTool = nil
                session.pendingPermissions.removeAll()
                session.pendingQuestion = nil
                if let path = session.transcriptPath, let model = session.model {
                    let usage = TranscriptParser.parseCumulativeUsage(at: path)
                    session.totalInputTokens = usage.inputTokens
                    session.totalOutputTokens = usage.outputTokens
                    session.totalCachedTokens = usage.cachedTokens
                    session.estimatedCost = CostCalculator.estimateCost(
                        model: model, inputTokens: usage.inputTokens,
                        outputTokens: usage.outputTokens, cachedTokens: usage.cachedTokens
                    )
                }
                // Post completion notification
                let lastMessage = session.transcriptPath
                    .flatMap { TranscriptParser.lastAssistantMessage(at: $0) } ?? ""
                NotificationCenter.default.post(
                    name: .agentNotchSessionCompleted,
                    object: sessionId,
                    userInfo: [
                        "projectName": session.originRepoName
                            ?? (session.cwd as NSString?)?.lastPathComponent ?? "Session",
                        "gitBranch": session.gitBranch as Any,
                        "isWorktree": (session.worktreeName != nil),
                        "message": lastMessage,
                        "pid": session.pid as Any,
                        "tty": session.tty as Any,
                    ]
                )

                manager.notifyChange()
            }

        case let .sessionEnded(sessionId):
            Log.events.info("sessionEnded id=\(sessionId)")
            manager.removeSession(id: sessionId)

        case let .compacting(sessionId):
            manager.session(for: sessionId)?.status = .compacting

        case .subagentStopped, .unknown:
            break
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
