import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Claude desktop session navigation")
@MainActor
struct ClaudeDesktopJumperTests {
    @Test("A resolved desktop session maps to the app's Code entry point")
    func desktopSessionDeepLink() throws {
        let session = UnifiedSession(id: "dcce9831-fd6d-4a46-9b97-5a4e739d162c", agentType: .claudeCode)
        session.claudeDesktopSessionId = "local_8bc26bcd-6e8d-40f5-bf61-bded302e785e"

        let url = try #require(ClaudeDesktopJumper.deepLink(for: session))

        #expect(
            url.absoluteString
                == "claude://claude.ai/claude-code-desktop/local_8bc26bcd-6e8d-40f5-bf61-bded302e785e"
        )
    }

    @Test("A session no desktop record claims has no destination")
    func unresolvedSessionHasNoDeepLink() {
        let session = UnifiedSession(id: "session-1", agentType: .claudeCode)

        #expect(ClaudeDesktopJumper.deepLink(for: session) == nil)
    }

    @Test("The CLI session ID is never used as the destination")
    func cliSessionIdIsNotTheDestination() throws {
        let session = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        session.claudeDesktopSessionId = "local_desktop-1"

        let url = try #require(ClaudeDesktopJumper.deepLink(for: session))

        #expect(url.absoluteString.contains("local_desktop-1"))
        #expect(!url.absoluteString.contains("cli-1"))
    }

    @Test("A Codex session never gets a Claude app destination")
    func codexSessionHasNoDeepLink() {
        let session = UnifiedSession(id: "thread-1", agentType: .codex)
        session.claudeDesktopSessionId = "local_1"

        #expect(ClaudeDesktopJumper.deepLink(for: session) == nil)
    }

    @Test("Completed and restored sessions remain linkable as local history")
    func historicalSessionsRemainLinkable() {
        let session = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        session.claudeDesktopSessionId = "local_1"

        session.presence = .inactive
        #expect(ClaudeDesktopJumper.deepLink(for: session) != nil)

        session.presence = .restored
        #expect(ClaudeDesktopJumper.deepLink(for: session) != nil)
    }

    @Test(
        "Invalid desktop identifiers are rejected",
        arguments: ["", ".", "..", "local id", "local\nid"]
    )
    func invalidDesktopSessionId(desktopSessionId: String) {
        #expect(ClaudeDesktopJumper.deepLink(desktopSessionId: desktopSessionId) == nil)
    }

    @Test("Reserved URL characters stay inside one encoded path component")
    func reservedCharactersAreEncoded() throws {
        let url = try #require(ClaudeDesktopJumper.deepLink(desktopSessionId: "local_a/b?c=#d"))

        #expect(url.absoluteString == "claude://claude.ai/claude-code-desktop/local_a%2Fb%3Fc%3D%23d")
    }

    @Test("Availability requires both a resolved session and a registered application")
    func availability() {
        let session = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        session.claudeDesktopSessionId = "local_1"
        var resolvedURL: URL?

        let available = ClaudeDesktopJumper.canJump(
            to: session,
            applicationURLFor: { url in
                resolvedURL = url
                return URL(fileURLWithPath: "/Applications/Claude.app")
            }
        )

        #expect(available)
        #expect(resolvedURL?.absoluteString == "claude://claude.ai/claude-code-desktop/local_1")
        #expect(
            ClaudeDesktopJumper.canJump(
                to: session,
                applicationURLFor: { _ in nil }
            ) == false
        )
    }

    @Test("A successful open closes the notch")
    func successfulOpenClosesNotch() {
        let session = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        session.claudeDesktopSessionId = "local_1"
        var openedURL: URL?
        var didClose = false

        let opened = ClaudeDesktopJumper.jump(
            to: session,
            openURL: {
                openedURL = $0
                return true
            },
            onOpened: { didClose = true }
        )

        #expect(opened)
        #expect(openedURL?.absoluteString == "claude://claude.ai/claude-code-desktop/local_1")
        #expect(didClose)
    }

    @Test("A rejected open keeps the notch visible")
    func failedOpenDoesNotCloseNotch() {
        let session = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        session.claudeDesktopSessionId = "local_1"
        var didClose = false

        let opened = ClaudeDesktopJumper.jump(
            to: session,
            openURL: { _ in false },
            onOpened: { didClose = true }
        )

        #expect(opened == false)
        #expect(didClose == false)
    }

    @Test("An unresolved session never reaches the URL opener")
    func unresolvedSessionDoesNotOpen() {
        let session = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        var didOpen = false
        var didClose = false

        let opened = ClaudeDesktopJumper.jump(
            to: session,
            openURL: { _ in
                didOpen = true
                return true
            },
            onOpened: { didClose = true }
        )

        #expect(!opened)
        #expect(!didOpen)
        #expect(!didClose)
    }
}
