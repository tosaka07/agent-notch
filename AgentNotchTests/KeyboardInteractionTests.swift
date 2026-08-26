import CoreGraphics
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Keyboard interaction tests")
struct KeyboardInteractionTests {
    private func stroke(
        keyCode: UInt16 = 0,
        characters: String = "",
        modifiers: KeyStroke.Modifiers = []
    ) -> KeyStroke {
        KeyStroke(keyCode: keyCode, characters: characters, modifiers: modifiers)
    }

    @Test("collection navigation resolves arrows, vim keys, Return, and Escape")
    func collectionNavigation() {
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(keyCode: 0x7E), in: .expanded
            ) == .movePrevious)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "j"), in: .notification
            ) == .moveNext)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(keyCode: 0x24), in: .expanded
            ) == .activate)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(keyCode: 0x35), in: .notification
            ) == .closePanel)
    }

    @Test("T jumps to the primary destination from an expanded card or session detail")
    func sessionDestinationShortcut() {
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "t"), in: .expanded
            ) == .jumpToSessionDestination)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "T"), in: .sessionDetail
            ) == .jumpToSessionDestination)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "t"), in: .notification
            ) == nil)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "t"), in: .question
            ) == nil)
    }

    @Test("expanded destination jump targets only the focused session")
    func expandedDestinationJumpTarget() {
        let available = UnifiedSession(id: "available", agentType: .claudeCode)
        available.pid = 42
        available.terminalAppName = "Terminal"
        available.terminalInfoResolved = true

        let unavailable = UnifiedSession(id: "unavailable", agentType: .codex)

        #expect(
            ExpandedKeyboardTargetResolver.focusedSession(
                focusedSessionID: available.id,
                sessions: [available, unavailable]
            ) === available)
        #expect(
            ExpandedKeyboardTargetResolver.focusedSession(
                focusedSessionID: unavailable.id,
                sessions: [available, unavailable]
            ) === unavailable)
        #expect(
            ExpandedKeyboardTargetResolver.focusedSession(
                focusedSessionID: nil,
                sessions: [available, unavailable]
            ) == nil)
    }

    @Test("permission has priority for Return and Escape")
    func permissionDecision() {
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(keyCode: 0x24), in: .permission
            ) == .activate)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(keyCode: 0x35), in: .permission
            ) == .cancel)
    }

    @Test("question navigation resolves selection, paging, preview, and numbers")
    func questionNavigation() {
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(keyCode: 0x31), in: .question
            ) == .toggleSelection)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(keyCode: 0x7B), in: .question
            ) == .previousQuestion)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "p"), in: .question
            ) == .togglePreview)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "3"), in: .question
            ) == .selectNumber(3))
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "f", modifiers: .control), in: .question
            ) == .nextQuestion)
    }

    @Test("page-specific modified shortcuts do not leak into other contexts")
    func pageSpecificShortcuts() {
        // Session detail reveals tools by holding Control, which arrives as a
        // flagsChanged peek rather than a chord, so ⌃-letter stays free here.
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "o", modifiers: .control), in: .sessionDetail
            ) == nil)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "r", modifiers: .command), in: .usage
            ) == .refresh)
        #expect(
            KeyboardShortcutResolver.command(
                for: stroke(characters: "r", modifiers: .command), in: .question
            ) == nil)
    }

    @Test("global shortcut descriptions become ordered bordered keycaps")
    func shortcutChordParsing() {
        #expect(
            ShortcutChord.fromDisplayDescription("⌥⇧↩")
                == ShortcutChord(keys: [.option, .shift, .returnKey])
        )
        #expect(ShortcutChord.fromDisplayDescription("esc") == .escape)
        #expect(ShortcutChord.fromDisplayDescription("") == nil)
    }

    @Test("an inactive app's first click inside expanded content engages instead of dismissing")
    func expandedGlobalClickClassification() {
        let notch = CGRect(x: 40, y: 90, width: 20, height: 10)
        let content = CGRect(x: 20, y: 40, width: 60, height: 60)

        #expect(
            HotZoneClickResolver.target(
                at: CGPoint(x: 30, y: 50),
                notchRect: notch,
                contentRect: content,
                isExpanded: true
            ) == .content)
        #expect(
            HotZoneClickResolver.target(
                at: CGPoint(x: 10, y: 10),
                notchRect: notch,
                contentRect: content,
                isExpanded: true
            ) == .outside)
        #expect(
            HotZoneClickResolver.target(
                at: CGPoint(x: 50, y: 95),
                notchRect: notch,
                contentRect: content,
                isExpanded: true
            ) == .notch)
    }

    @Test("permission submission stays loading and rejects a second decision")
    func permissionSubmissionState() {
        var state = PermissionSubmissionState()

        #expect(!state.isSubmitting)
        let didBegin = state.begin(.approve)
        #expect(didBegin)
        #expect(state.isSubmitting)
        #expect(state.decision == .approve)
        let acceptedSecondDecision = state.begin(.deny)
        #expect(!acceptedSecondDecision)

        state.finish()
        #expect(!state.isSubmitting)
        #expect(state.decision == nil)
    }
}
