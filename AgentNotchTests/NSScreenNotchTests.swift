import AppKit
import Testing

@testable import AgentNotch

@Suite("NSScreen notch helpers")
struct NSScreenNotchTests {
    @Test("System main resolves the display designated by Core Graphics")
    @MainActor
    func systemMainDisplay() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let expected =
            screens.first(where: { $0.displayID == CGMainDisplayID() })
            ?? screens[0]

        #expect(NSScreen.systemMain?.displayID == expected.displayID)
    }

    @Test("Built-in resolution never substitutes an external display")
    @MainActor
    func builtinDisplay() {
        guard let builtin = NSScreen.builtin else { return }

        #expect(builtin.isBuiltinDisplay)
    }
}
