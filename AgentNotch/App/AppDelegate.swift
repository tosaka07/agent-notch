import AppKit
import SwiftUI

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

    // MARK: - Screen Observer

    private func setupScreenObserver() {
        let observer = ScreenObserver()
        observer.onScreenChanged = { [weak self] in
            self?.recreateNotchOverlay()
        }
        screenObserver = observer
    }

    private func recreateNotchOverlay() {
        windowController?.close()
        windowController = nil
        setupNotchOverlay()
    }

    // MARK: - Socket Server

    private func startSocketServer() {
        let manager = sessionManager
        do {
            let server = try SocketServer { message in
                let event = ClaudeEventParser.parse(message)
                Task { @MainActor in
                    AppDelegate.processEvent(event, manager: manager)
                }
                // TODO: For PermissionRequest, keep socket open and return response later
                return ["status": "ok"]
            }
            server.start()
            socketServer = server
        } catch {
            print("[AgentNotch] Failed to start socket server: \(error)")
        }
    }

    @MainActor
    static func processEvent(_ event: ClaudeEvent, manager: SessionManager) {
        defer { manager.notifyChange() }

        switch event {
        case let .sessionStarted(info):
            let session = manager.getOrCreateSession(
                id: info.sessionId,
                agentType: .claudeCode
            )
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
                id: info.toolUseId,
                name: info.toolName,
                summary: info.summary,
                input: info.toolInput,
                startedAt: Date(),
                status: .running
            )
            session.toolCallCount += 1

        case let .toolCompleted(info):
            if let session = manager.session(for: info.sessionId) {
                if var tool = session.currentTool, tool.id == info.toolUseId {
                    tool.status = .succeeded
                    tool.completedAt = Date()
                    session.recentTools.insert(tool, at: 0)
                    if session.recentTools.count > 50 {
                        session.recentTools.removeLast()
                    }
                }
                session.currentTool = nil
                session.status = .thinking
            }

        case let .toolFailed(info):
            if let session = manager.session(for: info.sessionId) {
                if var tool = session.currentTool, tool.id == info.toolUseId {
                    tool.status = .failed
                    tool.completedAt = Date()
                    session.recentTools.insert(tool, at: 0)
                    if session.recentTools.count > 50 {
                        session.recentTools.removeLast()
                    }
                }
                session.currentTool = nil
                session.status = .thinking
            }

        case let .permissionRequested(info):
            let session = manager.session(for: info.sessionId)
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: .claudeCode)
            session.status = .permissionWaiting
            session.pendingPermissions.append(PermissionRequest(
                id: UUID().uuidString,
                agentType: .claudeCode,
                sessionId: info.sessionId,
                toolName: info.toolName,
                toolInput: info.toolInput,
                timestamp: Date(),
                canRespond: true  // TODO: wire up actual socket response
            ))

        case let .notification(sessionId, type, _):
            if type == "idle_prompt" {
                let session = manager.session(for: sessionId)
                    ?? manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
                session.status = .idle
            }

        case let .sessionIdle(sessionId):
            if let session = manager.session(for: sessionId) {
                session.status = .idle
                session.pendingPermissions.removeAll()
                if let path = session.transcriptPath, let model = session.model {
                    let usage = TranscriptParser.parseCumulativeUsage(at: path)
                    session.totalInputTokens = usage.inputTokens
                    session.totalOutputTokens = usage.outputTokens
                    session.totalCachedTokens = usage.cachedTokens
                    session.estimatedCost = CostCalculator.estimateCost(
                        model: model,
                        inputTokens: usage.inputTokens,
                        outputTokens: usage.outputTokens,
                        cachedTokens: usage.cachedTokens
                    )
                }
            }

        case let .sessionEnded(sessionId):
            // Remove session from active list
            manager.removeSession(id: sessionId)

        case let .compacting(sessionId):
            manager.session(for: sessionId)?.status = .compacting

        case .subagentStopped:
            break

        case .unknown:
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

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }

    @objc private func clearSessions() {
        sessionManager.removeAllSessions()
        sessionManager.notifyChange()
    }
}
