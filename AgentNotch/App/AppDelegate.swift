import AgentNotchCore
import AppKit
import Network
import SwiftUI

extension Notification.Name {
    static let agentNotchAutoExpand = Notification.Name("agentNotchAutoExpand")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: NotchWindowController?
    private var socketServer: SocketServer?
    private var screenObserver: ScreenObserver?
    let sessionManager = SessionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupNotchOverlay()
        setupScreenObserver()
        startSocketServer()
        HookInstaller.installIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }

    // MARK: - Notch Overlay

    private func setupNotchOverlay() {
        guard let screen = NSScreen.builtin else { return }
        let controller = NotchWindowController(screen: screen)
        let contentView = NotchContentView(sessionManager: sessionManager)
        controller.show(contentView: contentView)
        windowController = controller
    }

    private func setupScreenObserver() {
        let observer = ScreenObserver()
        observer.onScreenChanged = { [weak self] in
            self?.windowController?.close()
            self?.windowController = nil
            self?.setupNotchOverlay()
        }
        screenObserver = observer
    }

    // MARK: - Socket Server

    private func startSocketServer() {
        let manager = sessionManager
        do {
            let server = try SocketServer { message, connection in
                let event = ClaudeEventParser.parse(message)
                let sessionId = message["session_id"] as? String ?? ""

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

                Task { @MainActor in
                    AppDelegate.processEvent(event, manager: manager)
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
    static func processEvent(_ event: ClaudeEvent, manager: SessionManager) {
        defer { manager.notifyChange() }

        switch event {
        case let .sessionStarted(info):
            let session = manager.getOrCreateSession(id: info.sessionId, agentType: .claudeCode)
            session.model = info.model
            session.cwd = info.cwd
            session.transcriptPath = info.transcriptPath
            session.status = .idle

        case let .userPrompt(sessionId):
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
            session.status = .thinking

        case let .toolStarted(info):
            let session = manager.session(for: info.sessionId)
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: .claudeCode)
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
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: .claudeCode)
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
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: .claudeCode)
            session.status = .permissionWaiting
            session.pendingQuestion = PendingQuestion(
                toolUseId: info.toolUseId, question: info.question, options: info.options
            )
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)

        case let .notification(sessionId, type, _):
            if type == "idle_prompt" {
                let session = manager.session(for: sessionId)
                    ?? manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
                session.status = .idle
            }

        case let .subagentStarted(sessionId, _):
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
            session.status = .subagentRunning

        case let .stopFailure(sessionId, errorType):
            let session = manager.session(for: sessionId)
                ?? manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
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
                manager.notifyChange()
                // Fade to idle after 3 seconds
                let sid = sessionId
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    if manager.session(for: sid)?.status == .done {
                        manager.session(for: sid)?.status = .idle
                        manager.notifyChange()
                    }
                }
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
