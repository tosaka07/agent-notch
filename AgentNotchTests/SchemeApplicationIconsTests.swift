import AppKit
import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Destination application icons")
@MainActor
struct SchemeApplicationIconsTests {
    @Test("A destination resolves to the icon of the app registered for its scheme")
    func resolvesRegisteredApplicationIcon() throws {
        let expected = NSImage(size: NSSize(width: 1, height: 1))
        var resolvedURLs: [URL] = []
        let icons = SchemeApplicationIcons(
            applicationURLFor: { url in
                resolvedURLs.append(url)
                return URL(fileURLWithPath: "/Applications/Claude.app")
            },
            loadIcon: { _ in expected }
        )

        let icon = icons.icon(for: try #require(URL(string: "claude://claude.ai/x")))

        #expect(icon === expected)
        #expect(resolvedURLs.map(\.absoluteString) == ["claude://claude.ai/x"])
    }

    @Test("Sessions of the same agent share one lookup")
    func lookupIsMemoisedPerScheme() throws {
        let expected = NSImage(size: NSSize(width: 1, height: 1))
        var lookups = 0
        let icons = SchemeApplicationIcons(
            applicationURLFor: { _ in
                lookups += 1
                return URL(fileURLWithPath: "/Applications/ChatGPT.app")
            },
            loadIcon: { _ in expected }
        )

        let first = icons.icon(for: try #require(URL(string: "codex://threads/one")))
        let second = icons.icon(for: try #require(URL(string: "codex://threads/two")))

        #expect(first === expected)
        #expect(second === expected)
        #expect(lookups == 1)
    }

    @Test("An unregistered scheme yields no icon, leaving the button its vendor mark")
    func unregisteredSchemeHasNoIcon() throws {
        let icons = SchemeApplicationIcons(
            applicationURLFor: { _ in nil },
            loadIcon: { _ in NSImage(size: NSSize(width: 1, height: 1)) }
        )

        #expect(icons.icon(for: try #require(URL(string: "codex://threads/one"))) == nil)
    }

    @Test("A registered app with no loadable icon yields no icon")
    func unloadableIconYieldsNothing() throws {
        let icons = SchemeApplicationIcons(
            applicationURLFor: { _ in URL(fileURLWithPath: "/Applications/Claude.app") },
            loadIcon: { _ in nil }
        )

        #expect(icons.icon(for: try #require(URL(string: "claude://claude.ai/x"))) == nil)
    }

    @Test("A failed lookup is retried, so installing the app later still shows its icon")
    func failedLookupIsNotCached() throws {
        let expected = NSImage(size: NSSize(width: 1, height: 1))
        var isInstalled = false
        let icons = SchemeApplicationIcons(
            applicationURLFor: { _ in
                isInstalled ? URL(fileURLWithPath: "/Applications/Claude.app") : nil
            },
            loadIcon: { _ in expected }
        )
        let url = try #require(URL(string: "claude://claude.ai/x"))

        #expect(icons.icon(for: url) == nil)
        isInstalled = true
        #expect(icons.icon(for: url) === expected)
    }

    @Test("A session with no destination never reaches Launch Services")
    func sessionsWithoutDestinationAreNotResolved() {
        var lookups = 0
        let icons = SchemeApplicationIcons(
            applicationURLFor: { _ in
                lookups += 1
                return URL(fileURLWithPath: "/Applications/Claude.app")
            },
            loadIcon: { _ in NSImage(size: NSSize(width: 1, height: 1)) }
        )
        // Claude Code session that no desktop record claims, and a Codex-only surface asked for the
        // Claude icon: neither produces a deep link.
        let unresolved = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        let codexSession = UnifiedSession(id: "thread-1", agentType: .codex)

        #expect(ClaudeDesktopJumper.applicationIcon(for: unresolved, icons: icons) == nil)
        #expect(ClaudeDesktopJumper.applicationIcon(for: codexSession, icons: icons) == nil)
        #expect(CodexAppJumper.applicationIcon(for: unresolved, icons: icons) == nil)
        #expect(lookups == 0)
    }

    @Test("Each jumper asks for the scheme its own destination uses")
    func jumpersResolveTheirOwnScheme() {
        var resolvedSchemes: [String] = []
        let icons = SchemeApplicationIcons(
            applicationURLFor: { url in
                resolvedSchemes.append(url.scheme ?? "")
                return URL(fileURLWithPath: "/Applications/Some.app")
            },
            loadIcon: { _ in NSImage(size: NSSize(width: 1, height: 1)) }
        )
        let desktopSession = UnifiedSession(id: "cli-1", agentType: .claudeCode)
        desktopSession.claudeDesktopSessionId = "local_1"
        let codexSession = UnifiedSession(id: "thread-1", agentType: .codex)

        #expect(ClaudeDesktopJumper.applicationIcon(for: desktopSession, icons: icons) != nil)
        #expect(CodexAppJumper.applicationIcon(for: codexSession, icons: icons) != nil)
        #expect(resolvedSchemes == ["claude", "codex"])
    }
}
