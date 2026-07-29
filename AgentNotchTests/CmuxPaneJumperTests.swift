import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("cmux pane selection")
struct CmuxPaneJumperTests {
    /// A real identifier cmux issued, in the shape its scripting dictionary returns.
    private let surfaceId = "370E71D2-CF19-4D2A-90FA-692949AC2A98"

    @Test("cmux is recognised by its bundle identifier, whatever its case")
    @MainActor
    func recognisesCmux() {
        #expect(CmuxPaneJumper.isCmux(bundleIdentifier: "com.cmuxterm.app"))
        #expect(CmuxPaneJumper.isCmux(bundleIdentifier: "com.CmuxTerm.app"))
        #expect(CmuxPaneJumper.isCmux(bundleIdentifier: "com.mitchellh.ghostty") == false)
        #expect(CmuxPaneJumper.isCmux(bundleIdentifier: nil) == false)
    }

    @Test("the focus script addresses the surface cmux published")
    @MainActor
    func buildsFocusScript() {
        let expected =
            "tell application id \"com.cmuxterm.app\" to focus terminal id "
            + "\"370E71D2-CF19-4D2A-90FA-692949AC2A98\""

        #expect(CmuxPaneJumper.focusScript(surfaceId: surfaceId) == expected)
    }

    /// The identifier lands inside an AppleScript string literal, so a value carrying a quote could
    /// append statements of its own. Only a UUID gets that far.
    @Test("an identifier that is not a UUID never reaches AppleScript")
    @MainActor
    func rejectsNonUUIDSurfaceIdentifier() {
        #expect(CmuxPaneJumper.focusScript(surfaceId: "\" to quit") == nil)
        #expect(CmuxPaneJumper.focusScript(surfaceId: "") == nil)
        #expect(CmuxPaneJumper.focusScript(surfaceId: "not-a-uuid") == nil)
    }

    @Test("the surface comes from the session's own process when it has one")
    @MainActor
    func readsSurfaceFromSessionProcess() {
        let resolved = CmuxPaneJumper.surfaceIdentifier(
            forProcessTree: 500,
            environmentOf: { $0 == 500 ? ["CMUX_SURFACE_ID": surfaceId] : nil },
            parentOf: { _ in
                Issue.record("walked past a process that had the variable")
                return 1
            }
        )

        #expect(resolved == surfaceId)
    }

    /// A tmux client, or a process picked off the TTY, can sit below the shell cmux started.
    @Test("the surface is found on an ancestor when the anchor does not carry it")
    @MainActor
    func readsSurfaceFromAncestor() {
        let environments: [Int32: [String: String]] = [
            500: ["TERM": "xterm-256color"],
            400: ["CMUX_SURFACE_ID": surfaceId],
        ]

        let resolved = CmuxPaneJumper.surfaceIdentifier(
            forProcessTree: 500,
            environmentOf: { environments[$0] },
            parentOf: { $0 == 500 ? 400 : 1 }
        )

        #expect(resolved == surfaceId)
    }

    @Test("an empty surface variable is treated as absent")
    @MainActor
    func skipsEmptySurfaceVariable() {
        let environments: [Int32: [String: String]] = [
            500: ["CMUX_SURFACE_ID": ""],
            400: ["CMUX_SURFACE_ID": surfaceId],
        ]

        let resolved = CmuxPaneJumper.surfaceIdentifier(
            forProcessTree: 500,
            environmentOf: { environments[$0] },
            parentOf: { $0 == 500 ? 400 : 1 }
        )

        #expect(resolved == surfaceId)
    }

    /// cmux itself runs without the variable, so a session outside cmux walks to the root.
    @Test("a process tree without the variable resolves to nothing")
    @MainActor
    func resolvesNothingOutsideCmux() {
        let resolved = CmuxPaneJumper.surfaceIdentifier(
            forProcessTree: 500,
            environmentOf: { _ in ["TERM": "xterm-ghostty"] },
            parentOf: { $0 == 500 ? 400 : 1 }
        )

        #expect(resolved == nil)
    }

    @Test("the walk stops at the depth limit instead of following a cycle")
    @MainActor
    func stopsAtDepthLimit() {
        var visited = 0

        let resolved = CmuxPaneJumper.surfaceIdentifier(
            forProcessTree: 500,
            environmentOf: { _ in
                visited += 1
                return [:]
            },
            parentOf: { $0 == 500 ? 400 : 500 },
            maximumDepth: 4
        )

        #expect(resolved == nil)
        #expect(visited == 4)
    }

    @Test("focusing runs the script for the resolved surface")
    @MainActor
    func focusesResolvedSurface() {
        var executed: [String] = []

        let didFocus = CmuxPaneJumper.focusPane(
            forProcessTree: 500,
            environmentOf: { $0 == 500 ? ["CMUX_SURFACE_ID": surfaceId] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: {
                executed.append($0)
                return true
            }
        )

        #expect(didFocus)
        #expect(executed == [CmuxPaneJumper.focusScript(surfaceId: surfaceId)])
    }

    @Test("no surface means no script, so the caller falls back to activating cmux")
    @MainActor
    func doesNotFocusWithoutSurface() {
        var didRunScript = false

        let didFocus = CmuxPaneJumper.focusPane(
            forProcessTree: 500,
            environmentOf: { _ in [:] },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: { _ in
                didRunScript = true
                return true
            }
        )

        #expect(didFocus == false)
        #expect(didRunScript == false)
    }

    /// Denied automation is permanent until the user changes it in System Settings. Sending the
    /// event anyway would only spend time failing on every jump.
    @Test("denied automation skips the script")
    @MainActor
    func skipsScriptWhenAutomationIsDenied() {
        var didRunScript = false

        let didFocus = CmuxPaneJumper.focusPane(
            forProcessTree: 500,
            environmentOf: { $0 == 500 ? ["CMUX_SURFACE_ID": surfaceId] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { false },
            runScript: { _ in
                didRunScript = true
                return true
            }
        )

        #expect(didFocus == false)
        #expect(didRunScript == false)
    }

    @Test("a script that fails reports no focus")
    @MainActor
    func reportsFailedScript() {
        let didFocus = CmuxPaneJumper.focusPane(
            forProcessTree: 500,
            environmentOf: { $0 == 500 ? ["CMUX_SURFACE_ID": surfaceId] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: { _ in false }
        )

        #expect(didFocus == false)
    }
}
