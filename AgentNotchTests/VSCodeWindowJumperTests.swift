import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("VS Code window raise")
struct VSCodeWindowJumperTests {
    private let editorPID: Int32 = 76081

    @Test("the VS Code family is recognised by bundle identifier, whatever its case")
    @MainActor
    func recognisesFamily() {
        #expect(VSCodeWindowJumper.isVSCodeFamily(bundleIdentifier: "com.microsoft.VSCode"))
        #expect(VSCodeWindowJumper.isVSCodeFamily(bundleIdentifier: "com.microsoft.vscode"))
        #expect(
            VSCodeWindowJumper.isVSCodeFamily(bundleIdentifier: "com.todesktop.230313mzl4w4u92"))
        #expect(VSCodeWindowJumper.isVSCodeFamily(bundleIdentifier: "com.cmuxterm.app") == false)
        #expect(VSCodeWindowJumper.isVSCodeFamily(bundleIdentifier: nil) == false)
    }

    @Test("the raise script matches the workspace against the window titles of one process")
    @MainActor
    func buildsRaiseScript() {
        let script = VSCodeWindowJumper.focusScript(
            applicationPID: editorPID,
            workspaceName: "agent-notch"
        )

        #expect(script?.contains("first process whose unix id is 76081") == true)
        #expect(script?.contains("every window whose name contains \"agent-notch\"") == true)
        #expect(script?.contains("perform action \"AXRaise\"") == true)
    }

    /// The name lands inside an AppleScript string literal, so a directory carrying a quote could
    /// append statements of its own.
    @Test("a workspace name carrying AppleScript syntax is escaped rather than interpolated")
    @MainActor
    func escapesWorkspaceName() {
        let script = VSCodeWindowJumper.focusScript(
            applicationPID: editorPID,
            workspaceName: "we\"ird\\path"
        )

        #expect(script?.contains("\"we\\\"ird\\\\path\"") == true)
    }

    @Test("a workspace name that cannot be quoted safely never reaches AppleScript")
    @MainActor
    func rejectsUnquotableWorkspaceName() {
        #expect(
            VSCodeWindowJumper.focusScript(applicationPID: editorPID, workspaceName: "") == nil)
        #expect(
            VSCodeWindowJumper.focusScript(applicationPID: editorPID, workspaceName: "a\nb") == nil)
    }

    @Test("the deepest path components are offered first, and only a few of them")
    @MainActor
    func ordersWorkspaceCandidates() {
        let candidates = VSCodeWindowJumper.workspaceCandidates(
            forWorkingDirectory: "/Users/me/workspace/projects/agent-notch"
        )

        #expect(candidates == ["agent-notch", "projects", "workspace"])
    }

    @Test("a working directory with no component names no window")
    @MainActor
    func hasNoCandidateAtRoot() {
        #expect(VSCodeWindowJumper.workspaceCandidates(forWorkingDirectory: "/").isEmpty)
    }

    @Test("the working directory comes from the session's own process when it has one")
    @MainActor
    func readsWorkingDirectoryFromSessionProcess() {
        let resolved = VSCodeWindowJumper.workingDirectory(
            forProcessTree: 500,
            environmentOf: { $0 == 500 ? ["PWD": "/Users/me/agent-notch"] : nil },
            parentOf: { _ in
                Issue.record("walked past a process that had the variable")
                return 1
            }
        )

        #expect(resolved == "/Users/me/agent-notch")
    }

    /// A hook's anchor can be a process started before the shell exported its own directory.
    @Test("the working directory is found on an ancestor when the anchor does not carry it")
    @MainActor
    func readsWorkingDirectoryFromAncestor() {
        let environments: [Int32: [String: String]] = [
            500: ["TERM": "xterm-256color"],
            400: ["PWD": "/Users/me/agent-notch"],
        ]

        let resolved = VSCodeWindowJumper.workingDirectory(
            forProcessTree: 500,
            environmentOf: { environments[$0] },
            parentOf: { $0 == 500 ? 400 : 1 }
        )

        #expect(resolved == "/Users/me/agent-notch")
    }

    /// `PWD` is an ordinary variable a user can set to anything. Only an absolute path names a
    /// directory the editor could have titled a window after.
    @Test("a working directory that is not an absolute path is ignored")
    @MainActor
    func ignoresRelativeWorkingDirectory() {
        let resolved = VSCodeWindowJumper.workingDirectory(
            forProcessTree: 500,
            environmentOf: { $0 == 500 ? ["PWD": "agent-notch"] : nil },
            parentOf: { _ in 1 }
        )

        #expect(resolved == nil)
    }

    @Test("the walk gives up rather than following the tree to launchd")
    @MainActor
    func stopsWalkingAtTheTop() {
        let resolved = VSCodeWindowJumper.workingDirectory(
            forProcessTree: 500,
            environmentOf: { _ in [:] },
            parentOf: { $0 - 1 }
        )

        #expect(resolved == nil)
    }

    @Test("the first workspace that names a window wins, and no further script runs")
    @MainActor
    func stopsAtTheFirstMatchingWindow() {
        var attempted: [String] = []

        let focused = VSCodeWindowJumper.focusWindow(
            forProcessTree: 500,
            applicationPID: editorPID,
            environmentOf: { $0 == 500 ? ["PWD": "/Users/me/projects/agent-notch"] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: { script in
                attempted.append(script)
                return script.contains("\"agent-notch\"")
            }
        )

        #expect(focused)
        #expect(attempted.count == 1)
    }

    /// A monorepo run starts inside a package, so the window is titled after an ancestor.
    @Test("a deeper working directory falls back to the ancestor that names a window")
    @MainActor
    func fallsBackToAnAncestorWorkspace() {
        var attempted: [String] = []

        let focused = VSCodeWindowJumper.focusWindow(
            forProcessTree: 500,
            applicationPID: editorPID,
            environmentOf: { $0 == 500 ? ["PWD": "/Users/me/agent-notch/packages/core"] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: { script in
                attempted.append(script)
                return script.contains("\"agent-notch\"")
            }
        )

        #expect(focused)
        #expect(attempted.count == 3)
    }

    /// The caller still activates the app, so a missed match costs the window, not the jump.
    @Test("no window titled after the workspace leaves the raise unapplied")
    @MainActor
    func reportsFailureWhenNoWindowMatches() {
        let focused = VSCodeWindowJumper.focusWindow(
            forProcessTree: 500,
            applicationPID: editorPID,
            environmentOf: { $0 == 500 ? ["PWD": "/Users/me/agent-notch"] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: { _ in false }
        )

        #expect(focused == false)
    }

    @Test("a denied automation permission runs no script at all")
    @MainActor
    func runsNoScriptWithoutAutomationPermission() {
        let focused = VSCodeWindowJumper.focusWindow(
            forProcessTree: 500,
            applicationPID: editorPID,
            environmentOf: { $0 == 500 ? ["PWD": "/Users/me/agent-notch"] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { false },
            runScript: { _ in
                Issue.record("sent an Apple event after automation was denied")
                return true
            }
        )

        #expect(focused == false)
    }

    @Test("a process tree with no working directory runs no script at all")
    @MainActor
    func runsNoScriptWithoutAWorkingDirectory() {
        let focused = VSCodeWindowJumper.focusWindow(
            forProcessTree: 500,
            applicationPID: editorPID,
            environmentOf: { _ in nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: { _ in
                Issue.record("ran a script without a workspace to match")
                return true
            }
        )

        #expect(focused == false)
    }
}
