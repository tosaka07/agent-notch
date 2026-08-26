import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Codex app session navigation")
@MainActor
struct CodexAppJumperTests {
    @Test("A Codex root session maps to the documented thread deep link")
    func codexSessionDeepLink() throws {
        let session = UnifiedSession(
            id: "019faa0d-0513-76c1-a2c6-0cb7627e9440",
            agentType: .codex
        )

        let url = try #require(CodexAppJumper.deepLink(for: session))

        #expect(
            url.absoluteString
                == "codex://threads/019faa0d-0513-76c1-a2c6-0cb7627e9440"
        )
    }

    @Test("A non-Codex session never gets a Codex app destination")
    func claudeSessionHasNoDeepLink() {
        let session = UnifiedSession(id: "thread-1", agentType: .claudeCode)

        #expect(CodexAppJumper.deepLink(for: session) == nil)
    }

    @Test("Completed and restored Codex sessions remain linkable as local history")
    func historicalSessionsRemainLinkable() {
        let session = UnifiedSession(id: "thread-1", agentType: .codex)

        session.presence = .inactive
        #expect(CodexAppJumper.deepLink(for: session) != nil)

        session.presence = .restored
        #expect(CodexAppJumper.deepLink(for: session) != nil)
    }

    @Test(
        "Invalid thread identifiers are rejected",
        arguments: ["", "unknown", ".", "..", "thread id", "thread\nid"]
    )
    func invalidThreadId(threadId: String) {
        #expect(CodexAppJumper.deepLink(threadId: threadId) == nil)
    }

    @Test("Reserved URL characters stay inside one encoded path component")
    func reservedCharactersAreEncoded() throws {
        let url = try #require(CodexAppJumper.deepLink(threadId: "thread/child?mode=#one"))

        #expect(url.absoluteString == "codex://threads/thread%2Fchild%3Fmode%3D%23one")
    }

    @Test("Availability requires both a valid Codex link and a registered application")
    func availability() {
        let session = UnifiedSession(id: "thread-1", agentType: .codex)
        var resolvedURL: URL?

        let available = CodexAppJumper.canJump(
            to: session,
            applicationURLFor: { url in
                resolvedURL = url
                return URL(fileURLWithPath: "/Applications/ChatGPT.app")
            }
        )

        #expect(available)
        #expect(resolvedURL?.absoluteString == "codex://threads/thread-1")
        #expect(
            CodexAppJumper.canJump(
                to: session,
                applicationURLFor: { _ in nil }
            ) == false
        )
    }

    @Test("A successful open closes the notch")
    func successfulOpenClosesNotch() {
        let session = UnifiedSession(id: "thread-1", agentType: .codex)
        var openedURL: URL?
        var didClose = false

        let opened = CodexAppJumper.jump(
            to: session,
            openURL: {
                openedURL = $0
                return true
            },
            onOpened: { didClose = true }
        )

        #expect(opened)
        #expect(openedURL?.absoluteString == "codex://threads/thread-1")
        #expect(didClose)
    }

    @Test("A rejected open keeps the notch visible")
    func failedOpenDoesNotCloseNotch() {
        let session = UnifiedSession(id: "thread-1", agentType: .codex)
        var didClose = false

        let opened = CodexAppJumper.jump(
            to: session,
            openURL: { _ in false },
            onOpened: { didClose = true }
        )

        #expect(opened == false)
        #expect(didClose == false)
    }

    @Test("An invalid session never reaches the URL opener")
    func invalidSessionDoesNotOpen() {
        let session = UnifiedSession(id: "thread-1", agentType: .claudeCode)
        var didOpen = false
        var didClose = false

        let opened = CodexAppJumper.jump(
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
