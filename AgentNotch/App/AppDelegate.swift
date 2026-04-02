import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: NotchWindowController?
    private var socketServer: SocketServer?
    private var screenObserver: ScreenObserver?
    private let sessionManager = SessionManager()

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
        var contentView = NotchContentView(sessionManager: sessionManager)
        contentView.viewModel.physicalNotchWidth = screen.notchSize.width
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

    nonisolated static func debugLog(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let path = "/tmp/agent-notch-debug.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    private func startSocketServer() {
        let manager = sessionManager
        do {
            let server = try SocketServer { message in
                AppDelegate.debugLog("Received: \(message["hook_event_name"] ?? "unknown") session=\(message["session_id"] ?? "?")")
                let event = ClaudeEventParser.parse(message)
                AppDelegate.debugLog("Parsed event: \(event)")
                Task { @MainActor in
                    AppDelegate.processEvent(event, manager: manager)
                    let allSessions = manager.sessions
                    AppDelegate.debugLog("Processed. sessions dict count: \(allSessions.count), active: \(manager.activeSessions.count), changeCount: \(manager.changeCount)")
                    for (id, s) in allSessions {
                        AppDelegate.debugLog("  session[\(id)] status=\(s.status) tool=\(s.currentTool?.name ?? "nil")")
                    }
                }
                return ["status": "ok"]
            }
            server.start()
            socketServer = server
        } catch {
            print("[AppDelegate] Failed to start socket server: \(error)")
        }
    }

    @MainActor
    static func processEvent(_ event: ClaudeEvent, manager: SessionManager) {
        defer { manager.changeCount += 1 }
        switch event {
        case let .sessionStarted(info):
            debugLog("sessionStarted: creating session \(info.sessionId), manager id=\(ObjectIdentifier(manager))")
            let session = manager.getOrCreateSession(
                id: info.sessionId,
                agentType: AgentType.from(source: info.source)
            )
            debugLog("sessionStarted: created, sessions count now=\(manager.sessions.count)")
            session.model = info.model
            session.cwd = info.cwd
            session.transcriptPath = info.transcriptPath
            session.status = .idle
            debugLog("sessionStarted: status set to idle, sessions count=\(manager.sessions.count)")

        case let .userPrompt(sessionId):
            if let session = manager.session(for: sessionId) {
                session.status = .thinking
            }

        case let .toolStarted(info):
            let session = manager.session(for: info.sessionId)
                ?? manager.getOrCreateSession(id: info.sessionId, agentType: .claudeCode)
            session.status = .toolRunning
            let tool = ToolInfo(
                id: info.toolUseId,
                name: info.toolName,
                summary: info.summary,
                input: info.toolInput,
                startedAt: Date(),
                status: .running
            )
            session.currentTool = tool
            session.toolCallCount += 1

        case let .toolCompleted(info):
            if let session = manager.session(for: info.sessionId) {
                if var tool = session.currentTool, tool.id == info.toolUseId {
                    tool.status = .succeeded
                    tool.completedAt = Date()
                    session.recentTools.append(tool)
                    if session.recentTools.count > 50 {
                        session.recentTools.removeFirst(session.recentTools.count - 50)
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
                    session.recentTools.append(tool)
                    if session.recentTools.count > 50 {
                        session.recentTools.removeFirst(session.recentTools.count - 50)
                    }
                }
                session.currentTool = nil
                session.status = .thinking
            }

        case let .permissionRequested(info):
            if let session = manager.session(for: info.sessionId) {
                session.status = .permissionWaiting
                let request = PermissionRequest(
                    id: UUID().uuidString,
                    agentType: session.agentType,
                    sessionId: info.sessionId,
                    toolName: info.toolName,
                    toolInput: info.toolInput,
                    timestamp: Date(),
                    canRespond: false
                )
                session.pendingPermissions.append(request)
            }

        case let .notification(sessionId, type, _):
            if type == "idle_prompt",
               let session = manager.session(for: sessionId)
            {
                session.status = .idle
            }

        case let .sessionIdle(sessionId):
            if let session = manager.session(for: sessionId) {
                session.status = .idle
                // Parse transcript for token usage
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
            if let session = manager.session(for: sessionId) {
                session.status = .completed
                session.endedAt = Date()
            }

        case let .compacting(sessionId):
            if let session = manager.session(for: sessionId) {
                session.status = .compacting
            }

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
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }
}

// MARK: - AgentType helper

extension AgentType {
    static func from(source: String?) -> AgentType {
        guard let source else { return .claudeCode }
        switch source.lowercased() {
        case "codex": return .codex
        case "gemini": return .geminiCLI
        default: return .claudeCode
        }
    }
}
