import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Terminal jump activation")
struct TerminalJumperTests {
    @Test("a rejected activation keeps the notch open")
    @MainActor
    func rejectedActivationKeepsNotchOpen() {
        var didClose = false

        let didJump = TerminalJumper.completeActivation(
            accepted: false,
            onActivated: { didClose = true }
        )

        #expect(didJump == false)
        #expect(didClose == false)
    }

    @Test("an accepted activation closes the notch")
    @MainActor
    func acceptedActivationClosesNotch() {
        var didClose = false

        let didJump = TerminalJumper.completeActivation(
            accepted: true,
            onActivated: { didClose = true }
        )

        #expect(didJump)
        #expect(didClose)
    }

    @Test("ChatGPT is not classified as a terminal application")
    func chatGPTIsNotATerminal() {
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "com.openai.chat",
                localizedName: "ChatGPT"
            ) == false
        )
    }

    @Test("supported terminal applications remain recognized")
    func supportedTerminalsRemainRecognized() {
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "com.apple.Terminal",
                localizedName: "Terminal"
            )
        )
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "com.googlecode.iterm2",
                localizedName: "iTerm2"
            )
        )
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "com.mitchellh.ghostty",
                localizedName: "Ghostty"
            )
        )
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "dev.warp.Warp-Stable",
                localizedName: "Warp"
            )
        )
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "org.alacritty",
                localizedName: "Alacritty"
            )
        )
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "net.kovidgoyal.kitty",
                localizedName: "kitty"
            )
        )
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "com.github.wez.wezterm",
                localizedName: "WezTerm"
            )
        )
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: "com.cmuxterm.app",
                localizedName: "cmux"
            )
        )
        #expect(
            TerminalJumper.isSupportedTerminalApplication(
                bundleIdentifier: nil,
                localizedName: "Terminal"
            )
        )
    }

    @Test("a Codex session shortcut opens its exact app thread")
    @MainActor
    func codexSessionUsesExactAppThread() {
        let session = UnifiedSession(id: "thread-1", agentType: .codex)
        session.pid = 42
        session.terminalInfoResolved = true
        var didOpenCodexApp = false
        var didOpenTerminal = false

        let didJump = SessionDestinationJumper.jump(
            to: session,
            canJumpToCodexApp: { _ in true },
            jumpToCodexApp: { _ in
                didOpenCodexApp = true
                return true
            },
            jumpToTerminal: { _, _ in
                didOpenTerminal = true
                return true
            }
        )

        #expect(didJump)
        #expect(didOpenCodexApp)
        #expect(didOpenTerminal == false)
    }

    @Test("a terminal-backed session shortcut still opens its terminal")
    @MainActor
    func terminalBackedSessionUsesTerminal() {
        let session = UnifiedSession(id: "terminal-session", agentType: .claudeCode)
        session.pid = 42
        session.terminalAppName = "Terminal"
        session.terminalInfoResolved = true
        var didOpenCodexApp = false
        var didOpenTerminal = false

        let didJump = SessionDestinationJumper.jump(
            to: session,
            canJumpToCodexApp: { _ in false },
            jumpToCodexApp: { _ in
                didOpenCodexApp = true
                return true
            },
            jumpToTerminal: { _, _ in
                didOpenTerminal = true
                return true
            }
        )

        #expect(didJump)
        #expect(didOpenCodexApp == false)
        #expect(didOpenTerminal)
    }

    @Test("a Codex App destination is shared by the visible button and T shortcut")
    @MainActor
    func codexAppIsPrimaryDestination() {
        let session = UnifiedSession(id: "thread-1", agentType: .codex)
        session.pid = 42
        session.terminalAppName = "Terminal"
        session.terminalInfoResolved = true

        let destination = SessionDestinationJumper.destination(
            for: session,
            canJumpToCodexApp: { _ in true }
        )

        #expect(destination == .codexApp)
    }

    @Test("a session with no verified destination does nothing")
    @MainActor
    func unavailableSessionHasNoDestination() {
        let session = UnifiedSession(id: "unavailable", agentType: .claudeCode)
        var attemptedCodexApp = false
        var attemptedTerminal = false

        let didJump = SessionDestinationJumper.jump(
            to: session,
            canJumpToCodexApp: { _ in false },
            jumpToCodexApp: { _ in
                attemptedCodexApp = true
                return true
            },
            jumpToTerminal: { _, _ in
                attemptedTerminal = true
                return true
            }
        )

        #expect(!didJump)
        #expect(!attemptedCodexApp)
        #expect(!attemptedTerminal)
    }
}
