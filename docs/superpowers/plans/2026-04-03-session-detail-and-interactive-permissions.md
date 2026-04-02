# Session Detail View + Interactive Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add session detail view with Markdown-rendered chat logs, cwd display in session cards, and interactive GUI for Permission/AskUserQuestion approval — the notch auto-expands when user action is needed.

**Architecture:** Session detail replaces the current fullPanel mode. Clicking a session in the expanded list navigates to a detail view showing Markdown-rendered chat history from the JSONL transcript. The socket server is modified to hold connections open for PermissionRequest events so the GUI can respond with approve/deny. The notch auto-expands when a permission or question event arrives.

**Tech Stack:** MarkdownUI (SwiftUI Markdown renderer), existing AgentNotchCore socket infrastructure, JSONL transcript parsing

---

## File Structure

```
AgentNotchCore/
  Services/
    TranscriptReader.swift       — NEW: parse JSONL into ChatEntry array
    SocketServer.swift           — MODIFY: support deferred responses (hold connection open)
    SocketConnection.swift       — MODIFY: support deferred response pattern
    ClaudeEventParser.swift      — MODIFY: add askQuestion event
  Models/
    ChatEntry.swift              — NEW: chat log entry model
    UnifiedSession.swift         — MODIFY: add pendingResponse field

AgentNotch/
  UI/
    NotchContentView.swift       — MODIFY: replace fullPanel with sessionDetail, add auto-expand
    SessionDetail/
      SessionDetailView.swift    — NEW: back button + header + scrollable chat log
      ChatMessageView.swift      — NEW: single message bubble (user/assistant/tool)
    Expanded/
      SessionCardView.swift      — NEW: extracted from NotchContentView, add cwd + tap handler
    Permission/
      PermissionBanner.swift     — NEW: approve/deny UI shown when permission is pending
      QuestionBanner.swift       — NEW: answer selection UI for AskUserQuestion

Package.swift                    — MODIFY: add MarkdownUI dependency
```

---

## Task 1: Add MarkdownUI dependency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add MarkdownUI to Package.swift**

In `Package.swift`, add to `dependencies`:
```swift
.package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
```

Add `"MarkdownUI"` to the AgentNotch GUI target dependencies (not Core — it's a SwiftUI library):
```swift
.executableTarget(
    name: "AgentNotch",
    dependencies: [
        "AgentNotchCore",
        "Defaults",
        .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui"),
    ],
    ...
```

- [ ] **Step 2: Build to verify dependency resolves**

```bash
swift build
```

Expected: Resolves and builds. MarkdownUI is available in the AgentNotch target.

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "deps: add MarkdownUI for Markdown rendering in session detail"
```

---

## Task 2: ChatEntry model + TranscriptReader

**Files:**
- Create: `AgentNotchCore/Models/ChatEntry.swift`
- Create: `AgentNotchCore/Services/TranscriptReader.swift`
- Create: `AgentNotchTests/TranscriptReaderTests.swift`

- [ ] **Step 1: Write failing tests**

Create `AgentNotchTests/TranscriptReaderTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentNotchCore

@Suite("TranscriptReader")
struct TranscriptReaderTests {
    @Test("Parses user message")
    func parsesUser() throws {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"Hello world"},"timestamp":"2026-04-03T12:00:00.000Z","sessionId":"s1"}
        """
        let tmpFile = NSTemporaryDirectory() + "test-\(UUID()).jsonl"
        try jsonl.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let entries = TranscriptReader.read(path: tmpFile, tail: 100)
        #expect(entries.count == 1)
        #expect(entries[0].role == .user)
        #expect(entries[0].textContent == "Hello world")
    }

    @Test("Parses assistant text message")
    func parsesAssistantText() throws {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi there!"}]},"sessionId":"s1"}
        """
        let tmpFile = NSTemporaryDirectory() + "test-\(UUID()).jsonl"
        try jsonl.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let entries = TranscriptReader.read(path: tmpFile, tail: 100)
        #expect(entries.count == 1)
        #expect(entries[0].role == .assistant)
        #expect(entries[0].textContent == "Hi there!")
    }

    @Test("Parses assistant tool_use")
    func parsesToolUse() throws {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/src/main.swift"}}]},"sessionId":"s1"}
        """
        let tmpFile = NSTemporaryDirectory() + "test-\(UUID()).jsonl"
        try jsonl.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let entries = TranscriptReader.read(path: tmpFile, tail: 100)
        #expect(entries.count == 1)
        #expect(entries[0].role == .assistant)
        #expect(entries[0].toolUses.count == 1)
        #expect(entries[0].toolUses[0].name == "Edit")
    }

    @Test("Skips system and non-message lines")
    func skipsSystem() throws {
        let jsonl = """
        {"type":"file-history-snapshot","snapshot":{}}
        {"type":"system","subtype":"stop_hook_summary"}
        {"type":"user","message":{"role":"user","content":"test"},"sessionId":"s1"}
        """
        let tmpFile = NSTemporaryDirectory() + "test-\(UUID()).jsonl"
        try jsonl.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let entries = TranscriptReader.read(path: tmpFile, tail: 100)
        #expect(entries.count == 1)
    }

    @Test("Tail limits entries from end")
    func tailLimits() throws {
        var lines: [String] = []
        for i in 0..<20 {
            lines.append("""
            {"type":"user","message":{"role":"user","content":"msg \(i)"},"sessionId":"s1"}
            """)
        }
        let tmpFile = NSTemporaryDirectory() + "test-\(UUID()).jsonl"
        try lines.joined(separator: "\n").write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let entries = TranscriptReader.read(path: tmpFile, tail: 5)
        #expect(entries.count == 5)
        #expect(entries[0].textContent == "msg 15")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter TranscriptReaderTests
```

Expected: FAIL — `TranscriptReader` and `ChatEntry` not found.

- [ ] **Step 3: Create ChatEntry model**

Create `AgentNotchCore/Models/ChatEntry.swift`:

```swift
import Foundation

public struct ChatEntry: Identifiable, Sendable {
    public let id: String
    public let role: Role
    public let textContent: String
    public let toolUses: [ToolUseEntry]
    public let timestamp: Date?

    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public struct ToolUseEntry: Sendable {
        public let name: String
        public let inputSummary: String

        public init(name: String, inputSummary: String) {
            self.name = name
            self.inputSummary = inputSummary
        }
    }

    public init(id: String = UUID().uuidString, role: Role, textContent: String, toolUses: [ToolUseEntry] = [], timestamp: Date? = nil) {
        self.id = id
        self.role = role
        self.textContent = textContent
        self.toolUses = toolUses
        self.timestamp = timestamp
    }
}
```

- [ ] **Step 4: Create TranscriptReader**

Create `AgentNotchCore/Services/TranscriptReader.swift`:

```swift
import Foundation

public enum TranscriptReader {
    /// Read chat entries from a JSONL transcript file.
    /// `tail` limits to the last N message entries (user + assistant only).
    public static func read(path: String, tail: Int = 50) -> [ChatEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return [] }

        let lines = content.components(separatedBy: .newlines)
        var entries: [ChatEntry] = []

        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""
            guard type == "user" || type == "assistant" else { continue }
            guard let message = json["message"] as? [String: Any] else { continue }

            let timestamp = (json["timestamp"] as? String).flatMap { iso8601Date($0) }
            let role: ChatEntry.Role = type == "user" ? .user : .assistant

            var textContent = ""
            var toolUses: [ChatEntry.ToolUseEntry] = []

            // User messages: content is a string
            if let contentStr = message["content"] as? String {
                textContent = contentStr
            }
            // Assistant messages: content is an array of blocks
            else if let contentArray = message["content"] as? [[String: Any]] {
                for block in contentArray {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "text", let text = block["text"] as? String {
                        textContent += text
                    } else if blockType == "tool_use" {
                        let name = block["name"] as? String ?? "unknown"
                        let input = block["input"] as? [String: Any] ?? [:]
                        let summary = summarizeToolInput(name: name, input: input)
                        toolUses.append(ChatEntry.ToolUseEntry(name: name, inputSummary: summary))
                    }
                }
            }

            // Skip entries with no content
            guard !textContent.isEmpty || !toolUses.isEmpty else { continue }

            let id = json["uuid"] as? String ?? UUID().uuidString
            entries.append(ChatEntry(id: id, role: role, textContent: textContent, toolUses: toolUses, timestamp: timestamp))
        }

        // Return last `tail` entries
        if entries.count > tail {
            return Array(entries.suffix(tail))
        }
        return entries
    }

    private static func summarizeToolInput(name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            let cmd = input["command"] as? String ?? ""
            return cmd.count > 40 ? String(cmd.prefix(40)) + "..." : cmd
        case "Edit", "Write", "Read":
            let path = input["file_path"] as? String ?? ""
            return (path as NSString).lastPathComponent
        case "Grep":
            return input["pattern"] as? String ?? ""
        case "Glob":
            return input["pattern"] as? String ?? ""
        default:
            return name
        }
    }

    private static func iso8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter TranscriptReaderTests
```

Expected: All 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add AgentNotchCore/Models/ChatEntry.swift AgentNotchCore/Services/TranscriptReader.swift AgentNotchTests/TranscriptReaderTests.swift
git commit -m "feat: add ChatEntry model and TranscriptReader for JSONL chat history parsing"
```

---

## Task 3: Session card with cwd + tap navigation

**Files:**
- Create: `AgentNotch/UI/Expanded/SessionCardView.swift`
- Modify: `AgentNotch/UI/NotchContentView.swift`

- [ ] **Step 1: Create SessionCardView (extracted from NotchContentView)**

Create `AgentNotch/UI/Expanded/SessionCardView.swift`:

```swift
import AgentNotchCore
import SwiftUI

struct SessionCardView: View {
    let session: UnifiedSession
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: agent + elapsed time
            HStack {
                StatusIndicator(status: session.status, size: 8)
                Text(session.agentType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(formatDuration(session.elapsedTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Model + cwd
            HStack(spacing: 8) {
                if let model = session.model {
                    Text(model)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
                if let cwd = session.cwd {
                    Text(shortenPath(cwd))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }
            }

            // Current tool
            if let tool = session.currentTool {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 8))
                    Text("\(tool.name): \(tool.summary)")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.green.opacity(0.8))
            }

            // Tokens + cost
            HStack(spacing: 12) {
                Label(TokenFormatter.format(session.totalInputTokens), systemImage: "arrow.down")
                Label(TokenFormatter.format(session.totalOutputTokens), systemImage: "arrow.up")
                Spacer()
                Text(CostCalculator.formatCost(session.estimatedCost))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        var short = path
        if short.hasPrefix(home) {
            short = "~" + short.dropFirst(home.count)
        }
        // Show last 2 components: ~/projects/agent-notch
        let components = short.split(separator: "/")
        if components.count > 3 {
            return "~/" + components.suffix(2).joined(separator: "/")
        }
        return short
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
```

- [ ] **Step 2: Update NotchContentView — replace fullPanel with sessionDetail navigation**

In `NotchContentView.swift`:

Replace the `NotchMode` enum:
```swift
enum NotchMode: Sendable, Equatable {
    case compact
    case expanded
    case sessionDetail(sessionId: String)
}
```

Update `NotchViewModel`:
- Remove `fullPanel` from `notchWidth`, `notchHeight`, `topCornerRadius`, `bottomCornerRadius` — replace with `sessionDetail`:
```swift
var notchWidth: CGFloat {
    switch mode {
    case .compact: physicalNotchWidth + expansionWidth
    case .expanded: 550
    case .sessionDetail: 650
    }
}

var notchHeight: CGFloat {
    switch mode {
    case .compact: physicalNotchHeight
    case .expanded: 400
    case .sessionDetail: 550
    }
}

var topCornerRadius: CGFloat {
    switch mode {
    case .compact: 6
    case .expanded, .sessionDetail: 12
    }
}

var bottomCornerRadius: CGFloat {
    switch mode {
    case .compact: 14
    case .expanded, .sessionDetail: 24
    }
}
```

Update `toggle()`:
```swift
func toggle() {
    switch mode {
    case .compact: mode = .expanded
    case .expanded: mode = .compact
    case .sessionDetail: mode = .expanded
    }
}
```

Add `showSession`:
```swift
func showSession(_ sessionId: String) {
    mode = .sessionDetail(sessionId: sessionId)
}

func backToList() {
    mode = .expanded
}
```

Update `contentForMode`:
```swift
@ViewBuilder
private var contentForMode: some View {
    switch viewModel.mode {
    case .compact:
        compactContent
    case .expanded:
        expandedContent
    case .sessionDetail(let sessionId):
        if let session = sessionManager.session(for: sessionId) {
            SessionDetailView(session: session, onBack: { viewModel.backToList() })
        } else {
            expandedContent
        }
    }
}
```

Replace the ForEach in `expandedContent` to use `SessionCardView`:
```swift
ForEach(sessions) { session in
    SessionCardView(session: session) {
        viewModel.showSession(session.id)
    }
}
```

Remove `sessionCard()`, `sessionCardFull()`, `fullPanelContent` methods entirely.

- [ ] **Step 3: Build**

```bash
swift build
```

Expected: Build succeeds (SessionDetailView is created in next task, use placeholder for now).

Create a temporary stub for SessionDetailView so the build passes:

Create `AgentNotch/UI/SessionDetail/SessionDetailView.swift`:
```swift
import AgentNotchCore
import SwiftUI

struct SessionDetailView: View {
    let session: UnifiedSession
    var onBack: () -> Void

    var body: some View {
        VStack {
            Text("Session Detail — placeholder")
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
swift build
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SessionCardView with cwd, replace fullPanel with sessionDetail navigation"
```

---

## Task 4: Session Detail View with Markdown chat log

**Files:**
- Modify: `AgentNotch/UI/SessionDetail/SessionDetailView.swift`
- Create: `AgentNotch/UI/SessionDetail/ChatMessageView.swift`

- [ ] **Step 1: Create ChatMessageView**

Create `AgentNotch/UI/SessionDetail/ChatMessageView.swift`:

```swift
import AgentNotchCore
import MarkdownUI
import SwiftUI

struct ChatMessageView: View {
    let entry: ChatEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Role label
            HStack(spacing: 4) {
                Image(systemName: entry.role == .user ? "person.fill" : "cpu")
                    .font(.system(size: 8))
                Text(entry.role == .user ? "You" : "Claude")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(entry.role == .user ? .blue.opacity(0.8) : .orange.opacity(0.8))

            // Text content as Markdown
            if !entry.textContent.isEmpty {
                Markdown(entry.textContent)
                    .markdownTheme(.agentNotch)
                    .textSelection(.enabled)
            }

            // Tool uses
            ForEach(Array(entry.toolUses.enumerated()), id: \.offset) { _, tool in
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.green.opacity(0.6))
                    Text("\(tool.name)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.8))
                    Text(tool.inputSummary)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.role == .user ? Color.white.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Markdown Theme

extension MarkdownUI.Theme {
    static let agentNotch = Theme()
        .text { configuration in
            configuration.label
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
        }
        .code { configuration in
            configuration.label
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.green.opacity(0.8))
        }
        .codeBlock { configuration in
            configuration.label
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .padding(6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .heading1 { configuration in
            configuration.label
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .heading2 { configuration in
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
}
```

- [ ] **Step 2: Implement SessionDetailView**

Replace `AgentNotch/UI/SessionDetail/SessionDetailView.swift`:

```swift
import AgentNotchCore
import SwiftUI

struct SessionDetailView: View {
    let session: UnifiedSession
    var onBack: () -> Void

    @State private var chatEntries: [ChatEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.top, 44)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider().overlay(Color.white.opacity(0.1))

            // Chat log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(chatEntries) { entry in
                            ChatMessageView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    loadChat()
                    scrollToBottom(proxy)
                }
                .onChange(of: chatEntries.count) {
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                StatusIndicator(status: session.status, size: 8)
                Text(session.agentType.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                if let cwd = session.cwd {
                    Text(shortenPath(cwd))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }

                Spacer()

                Text(formatDuration(session.elapsedTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 12) {
                if let model = session.model {
                    Text(model).font(.system(size: 9))
                }
                Text("\(TokenFormatter.format(session.totalInputTokens))↓ \(TokenFormatter.format(session.totalOutputTokens))↑")
                    .font(.system(size: 9, design: .monospaced))
                Text(CostCalculator.formatCost(session.estimatedCost))
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func loadChat() {
        guard let path = session.transcriptPath else { return }
        chatEntries = TranscriptReader.read(path: path, tail: 50)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = chatEntries.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        var short = path
        if short.hasPrefix(home) {
            short = "~" + short.dropFirst(home.count)
        }
        let components = short.split(separator: "/")
        if components.count > 3 {
            return "~/" + components.suffix(2).joined(separator: "/")
        }
        return short
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
swift build
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add SessionDetailView with Markdown-rendered chat history from JSONL"
```

---

## Task 5: Socket deferred response for PermissionRequest

**Files:**
- Modify: `AgentNotchCore/Services/SocketServer.swift`
- Modify: `AgentNotchCore/Services/SocketConnection.swift`
- Modify: `AgentNotchCore/Services/HookHandler.swift`
- Modify: `AgentNotchCore/Models/UnifiedSession.swift`

This is the core change that enables GUI approve/deny. The pattern (from Claude Island):
1. CLI sends PermissionRequest to socket
2. Socket server holds the NWConnection open (does NOT send response yet)
3. GUI shows approve/deny buttons
4. User clicks → server sends response on the held connection → connection closes
5. CLI receives response → prints hook output JSON → Claude Code reads it

- [ ] **Step 1: Add PendingResponse to SocketServer**

Modify `AgentNotchCore/Services/SocketServer.swift` — add a pending response store:

```swift
// Add at top of SocketServer class
public struct PendingResponse: Sendable {
    public let sessionId: String
    public let toolUseId: String
    public let connection: NWConnection
    public let receivedAt: Date
}

// Add property
private let _pending = NWProtocolFramer.LockedDict<String, PendingResponse>()

// Add public methods
public func respondToPermission(toolUseId: String, decision: String, reason: String?) {
    guard let pending = _pending.remove(toolUseId) else { return }
    let response: [String: Any] = [
        "hookSpecificOutput": [
            "hookEventName": "PermissionRequest",
            "decision": [
                "behavior": decision,
                "message": reason ?? ""
            ]
        ]
    ]
    if let data = try? SocketProtocol.encode(response) {
        pending.connection.send(content: data, completion: .contentProcessed { _ in
            pending.connection.cancel()
        })
    }
}

public func addPending(_ pending: PendingResponse) {
    _pending.set(pending.toolUseId, pending)
}

public func cancelPending(sessionId: String) {
    for (key, val) in _pending.all() {
        if val.sessionId == sessionId {
            val.connection.cancel()
            _pending.remove(key)
        }
    }
}
```

Add `LockedDict` helper next to the existing `LockedArray`:
```swift
final class LockedDict<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private var dict: [Key: Value] = [:]
    private let lock = NSLock()

    func set(_ key: Key, _ value: Value) {
        lock.lock(); dict[key] = value; lock.unlock()
    }

    @discardableResult
    func remove(_ key: Key) -> Value? {
        lock.lock(); let v = dict.removeValue(forKey: key); lock.unlock(); return v
    }

    func all() -> [(Key, Value)] {
        lock.lock(); let items = Array(dict); lock.unlock(); return items
    }
}
```

- [ ] **Step 2: Modify SocketConnection to support deferred response**

In `SocketConnection.swift`, change `onMessage` to return an optional response — if nil, don't close the connection:

Change the callback type to include the NWConnection:
```swift
public let onMessage: @Sendable ([String: Any], NWConnection) -> [String: Any]?
```

In `receiveMessage()`, if `onMessage` returns nil, do NOT send a response or close the connection — leave it open for later.

- [ ] **Step 3: Modify HookHandler CLI to wait for response on PermissionRequest**

In `HookHandler.swift`, the CLI already waits for a response (it calls `recv` after `send`). The socket server just needs to hold the connection and respond later. No CLI change needed — the blocking `recv` will wait until the GUI responds.

But verify the timeout is long enough. Currently `timeout = 300` (5 min). PermissionRequest in `HookInstaller` has `timeout: 86400`. The CLI socket timeout should match:

```swift
// In HookHandler.sendToSocket, change:
private static let timeout: TimeInterval = 86400  // Match hook timeout
```

- [ ] **Step 4: Add pendingPermission tracking to UnifiedSession**

Already has `pendingPermissions: [PermissionRequest]`. Add a `toolUseId` field to track which socket to respond on:

In `PermissionRequest.swift`, the `id` field already exists but we need the `toolUseId` from the hook event. Add it:
```swift
public struct PermissionRequest: Identifiable, Sendable {
    public let id: String
    public let agentType: AgentType
    public let sessionId: String
    public let toolName: String
    public let toolInput: [String: String]
    public let toolUseId: String  // NEW — for socket response
    public let timestamp: Date
    public let canRespond: Bool
    // ... init
}
```

- [ ] **Step 5: Build and verify**

```bash
swift build
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: socket server holds connection open for PermissionRequest deferred response"
```

---

## Task 6: Permission banner UI + auto-expand

**Files:**
- Create: `AgentNotch/UI/Permission/PermissionBanner.swift`
- Modify: `AgentNotch/UI/NotchContentView.swift`
- Modify: `AgentNotch/App/AppDelegate.swift`

- [ ] **Step 1: Create PermissionBanner**

Create `AgentNotch/UI/Permission/PermissionBanner.swift`:

```swift
import AgentNotchCore
import SwiftUI

struct PermissionBanner: View {
    let permission: PermissionRequest
    var onApprove: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14))
                Text("Permission Required")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Tool info
            VStack(alignment: .leading, spacing: 4) {
                Text(permission.toolName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))

                // Show tool input preview
                ForEach(Array(permission.toolInput.prefix(3)), id: \.key) { key, value in
                    Text("\(key): \(String(value.prefix(80)))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Action buttons
            HStack(spacing: 12) {
                Button { onApprove() } label: {
                    Text("Approve")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button { onDeny() } label: {
                    Text("Deny")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }
}
```

- [ ] **Step 2: Auto-expand on PermissionRequest**

In `AppDelegate.swift`, when processing `permissionRequested`:
```swift
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
        toolUseId: info.toolUseId,  // pass through from PreToolUse cache
        timestamp: Date(),
        canRespond: true
    ))
    // Auto-expand the notch
    NotificationCenter.default.post(name: .agentNotchAutoExpand, object: info.sessionId)
```

Add notification name:
```swift
extension Notification.Name {
    static let agentNotchAutoExpand = Notification.Name("agentNotchAutoExpand")
}
```

In `NotchContentView`, observe the notification:
```swift
.onReceive(NotificationCenter.default.publisher(for: .agentNotchAutoExpand)) { notification in
    if let sessionId = notification.object as? String {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            viewModel.showSession(sessionId)
        }
    }
}
```

- [ ] **Step 3: Wire approve/deny to socket server**

In `AppDelegate`, add methods accessible from the UI:
```swift
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
```

- [ ] **Step 4: Show PermissionBanner in SessionDetailView**

In `SessionDetailView`, add at the top of the chat log area:
```swift
// Before the ScrollView
if let pending = session.pendingPermissions.first {
    PermissionBanner(
        permission: pending,
        onApprove: {
            (NSApp.delegate as? AppDelegate)?.approvePermission(
                sessionId: session.id, toolUseId: pending.toolUseId
            )
        },
        onDeny: {
            (NSApp.delegate as? AppDelegate)?.denyPermission(
                sessionId: session.id, toolUseId: pending.toolUseId, reason: "Denied via Agent Notch"
            )
        }
    )
    .padding(.horizontal, 12)
}
```

Also show in expanded mode if there's a pending permission:
```swift
// In expandedContent, before the ScrollView
let pendingSession = sessions.first(where: { !$0.pendingPermissions.isEmpty })
if let pending = pendingSession, let perm = pending.pendingPermissions.first {
    PermissionBanner(
        permission: perm,
        onApprove: { ... },
        onDeny: { ... }
    )
    .padding(.horizontal, 16)
}
```

- [ ] **Step 5: Build and verify**

```bash
swift build
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: permission approve/deny via GUI with auto-expanding notch and socket deferred response"
```

---

## Task 7: AskUserQuestion support

**Files:**
- Modify: `AgentNotchCore/Services/ClaudeEventParser.swift`
- Modify: `AgentNotchCore/Services/HookInstaller.swift`
- Create: `AgentNotch/UI/Permission/QuestionBanner.swift`

Claude Code's `AskUserQuestion` hook provides questions with optional multiple-choice answers. The hook JSON looks like:
```json
{
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "questions": [{"question": "Which approach?", "options": ["A", "B", "C"]}]
  }
}
```

- [ ] **Step 1: Update ClaudeEventParser to detect AskUserQuestion**

In `ClaudeEventParser.swift`, the `PreToolUse` case already captures `tool_name`. Add a new event case:

```swift
// Add to ClaudeEvent enum:
case askQuestion(sessionId: String, toolUseId: String, question: String, options: [String])
```

In the `PreToolUse` parsing:
```swift
case "PreToolUse":
    let toolName = json["tool_name"] as? String ?? ""

    // Special handling for AskUserQuestion
    if toolName == "AskUserQuestion" {
        let rawInput = json["tool_input"] as? [String: Any] ?? [:]
        let toolUseId = json["tool_use_id"] as? String ?? UUID().uuidString
        let questions = rawInput["questions"] as? [[String: Any]] ?? []
        let firstQ = questions.first
        let question = firstQ?["question"] as? String ?? "Question from Claude"
        let options = firstQ?["options"] as? [String] ?? []
        return .askQuestion(sessionId: sessionId, toolUseId: toolUseId, question: question, options: options)
    }

    // ... rest of PreToolUse handling
```

- [ ] **Step 2: Create QuestionBanner**

Create `AgentNotch/UI/Permission/QuestionBanner.swift`:

```swift
import AgentNotchCore
import SwiftUI

struct QuestionBanner: View {
    let question: String
    let options: [String]
    var onAnswer: (String) -> Void

    @State private var textAnswer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14))
                Text("Claude is asking")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(question)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))

            if options.isEmpty {
                // Free text input
                HStack {
                    TextField("Type your answer...", text: $textAnswer)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button { onAnswer(textAnswer) } label: {
                        Text("Send")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(textAnswer.isEmpty)
                }
            } else {
                // Multiple choice
                FlowLayout(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button { onAnswer(option) } label: {
                            Text(option)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
    }
}

/// Simple flow layout for option buttons
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
```

- [ ] **Step 3: Handle askQuestion in AppDelegate**

In `processEvent`:
```swift
case let .askQuestion(sessionId, toolUseId, question, options):
    let session = manager.session(for: sessionId)
        ?? manager.getOrCreateSession(id: sessionId, agentType: .claudeCode)
    session.status = .permissionWaiting
    session.pendingQuestion = PendingQuestion(toolUseId: toolUseId, question: question, options: options)
    NotificationCenter.default.post(name: .agentNotchAutoExpand, object: sessionId)
```

Add `PendingQuestion` to `UnifiedSession`:
```swift
public struct PendingQuestion: Sendable {
    public let toolUseId: String
    public let question: String
    public let options: [String]
    public init(toolUseId: String, question: String, options: [String]) {
        self.toolUseId = toolUseId; self.question = question; self.options = options
    }
}

// In UnifiedSession:
public var pendingQuestion: PendingQuestion?
```

- [ ] **Step 4: Show QuestionBanner in SessionDetailView**

```swift
if let question = session.pendingQuestion {
    QuestionBanner(
        question: question.question,
        options: question.options
    ) { answer in
        (NSApp.delegate as? AppDelegate)?.answerQuestion(
            sessionId: session.id, toolUseId: question.toolUseId, answer: answer
        )
    }
    .padding(.horizontal, 12)
}
```

- [ ] **Step 5: Build and verify**

```bash
swift build
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: AskUserQuestion support with auto-expanding notch and option/text input UI"
```

---

## Task 8: Live chat refresh + clean up

**Files:**
- Modify: `AgentNotch/UI/SessionDetail/SessionDetailView.swift`
- Modify: `AgentNotch/UI/NotchContentView.swift`

- [ ] **Step 1: Auto-refresh chat log on new events**

In `SessionDetailView`, add a timer or respond to sessionManager changes:

```swift
@ObservedObject var sessionManager: SessionManager  // pass from parent

// Add to body:
.onChange(of: sessionManager.activeSessions.count) {
    loadChat()
}
```

Or simpler — reload on session status change. Since `sessionManager.notifyChange()` is called on every event, the view will re-render and we can reload:

```swift
.onReceive(sessionManager.objectWillChange) {
    loadChat()
}
```

- [ ] **Step 2: Clean up old code**

Remove `fullPanelContent`, `sessionCardFull()` from `NotchContentView` if not already removed.

Remove `formatDuration` duplication — extract to a shared utility if needed.

- [ ] **Step 3: Build and test**

```bash
swift build && swift test
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: live chat refresh on events, cleanup old fullPanel code"
```
