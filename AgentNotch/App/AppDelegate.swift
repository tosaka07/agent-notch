import AgentNotchCore
import AppKit
import Defaults
import Network
import SwiftUI

extension Notification.Name {
    static let agentNotchAutoExpand = Notification.Name("agentNotchAutoExpand")
    static let agentNotchSessionCompleted = Notification.Name("agentNotchSessionCompleted")
    static let agentNotchSessionSwept = Notification.Name("agentNotchSessionSwept")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: NotchWindowController?
    private var socketServer: SocketServer?
    private var screenObserver: ScreenObserver?
    private var focusedScreenTracker: FocusedScreenTracker?
    private var cleanupTimer: Timer?
    let sessionManager = SessionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupNotchOverlay(on: NSScreen.builtin ?? NSScreen.screens[0])
        setupScreenObserver()
        setupFocusedScreenTracker()
        startSocketServer()
        startSessionCleanupTimer()
        HookInstaller.installIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }

    // MARK: - Notch Overlay

    private func setupNotchOverlay(on screen: NSScreen, force: Bool = false) {
        // Skip if already showing on this screen (unless forced by screen parameter change)
        if !force, let current = windowController?.screen, current.displayID == screen.displayID { return }
        let rawMode = windowController?.currentMode ?? .compact
        // Notification state is @State-local and won't survive re-creation — reset to compact
        let previousMode = rawMode == .notification ? .compact : rawMode
        windowController?.close()
        windowController = nil
        let controller = NotchWindowController(screen: screen)
        let contentView = NotchContentView(
            sessionManager: sessionManager, notchSize: screen.notchSize, initialMode: previousMode
        )
        controller.show(contentView: contentView)
        windowController = controller
    }

    private func setupScreenObserver() {
        let observer = ScreenObserver()
        observer.onScreenChanged = { [weak self] in
            guard let self else { return }
            // Screen params changed (display connected/disconnected). Re-evaluate target.
            let currentID = self.windowController?.screen.displayID
            if let currentID, NSScreen.screens.contains(where: { $0.displayID == currentID }) {
                // Current screen still exists — recreate to pick up new geometry
                if let screen = NSScreen.screens.first(where: { $0.displayID == currentID }) {
                    self.setupNotchOverlay(on: screen, force: true)
                }
            } else {
                // Current screen gone — fall back
                self.setupNotchOverlay(on: NSScreen.builtin ?? NSScreen.screens[0])
            }
        }
        screenObserver = observer
    }

    private func setupFocusedScreenTracker() {
        let tracker = FocusedScreenTracker()
        tracker.onScreenChanged = { [weak self] screen in
            self?.setupNotchOverlay(on: screen)
        }
        tracker.start()
        focusedScreenTracker = tracker
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

                // For PermissionRequest / AskQuestion: hold connection open
                let isDeferred: Bool
                switch event {
                case .permissionRequested(let info):
                    let toolUseId = info.toolUseId.isEmpty ? UUID().uuidString : info.toolUseId
                    // Store pending response on the server via a posted notification
                    let pending = PendingSocketResponse(
                        sessionId: sessionId, toolUseId: toolUseId,
                        connection: connection, receivedAt: Date()
                    )
                    Task { @MainActor in
                        // Access socketServer on MainActor
                        (NSApp.delegate as? AppDelegate)?.socketServer?.addPending(pending)
                    }
                    isDeferred = true
                case .askQuestion(let info):
                    let pending = PendingSocketResponse(
                        sessionId: sessionId, toolUseId: info.toolUseId,
                        connection: connection, receivedAt: Date()
                    )
                    Task { @MainActor in
                        (NSApp.delegate as? AppDelegate)?.socketServer?.addPending(pending)
                    }
                    isDeferred = true
                default:
                    isDeferred = false
                }

                // Extract common fields available on all hook events
                let cwd = message["cwd"] as? String
                let transcriptPath = message["transcript_path"] as? String

                Task { @MainActor in
                    AppDelegate.processEvent(event, agentType: agentType, manager: manager)
                    // Backfill cwd/transcriptPath on every event (may have been missing on auto-created sessions)
                    if let session = manager.session(for: sessionId) {
                        session.lastActivityAt = Date()
                        if session.cwd == nil, let cwd { session.cwd = cwd }
                        if session.transcriptPath == nil, let transcriptPath { session.transcriptPath = transcriptPath }
                    }
                }

                return isDeferred ? nil : ["status": "ok"]
            }
            server.start()
            socketServer = server
        } catch {
            print("[AgentNotch] Failed to start socket server: \(error)")
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
            let session = manager.getOrCreateSession(id: info.sessionId, agentType: agentType)
            session.model = info.model
            session.cwd = info.cwd
            session.transcriptPath = info.transcriptPath
            session.status = .idle

        case let .userPrompt(sessionId):
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
            session.status = .thinking

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
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: agentType)
            session.status = .error
            session.currentTool = nil

        case let .compactingDone(sessionId):
            if let session = manager.session(for: sessionId) {
                session.status = .thinking
            }

        case let .sessionIdle(sessionId):
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
                    ]
                )

                manager.notifyChange()
            }

        case let .sessionEnded(sessionId):
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
