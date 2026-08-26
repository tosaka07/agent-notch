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

    @Test("both scripts address the editor by process ID rather than by name")
    @MainActor
    func addressesOneProcess() {
        let listing = VSCodeWindowJumper.windowTitleScript(applicationPID: editorPID)
        let raise = VSCodeWindowJumper.focusScript(
            applicationPID: editorPID,
            windowTitle: "agent-notch"
        )

        #expect(listing.contains("first process whose unix id is 76081"))
        #expect(raise?.contains("first process whose unix id is 76081") == true)
    }

    @Test("the raise script names the one window the workspace resolved to")
    @MainActor
    func buildsRaiseScript() {
        let script = VSCodeWindowJumper.focusScript(
            applicationPID: editorPID,
            windowTitle: "main.swift — agent-notch"
        )

        #expect(script?.contains("first window whose name is \"main.swift — agent-notch\"") == true)
        #expect(script?.contains("perform action \"AXRaise\"") == true)
    }

    /// The title lands inside an AppleScript string literal, so one carrying a quote could append
    /// statements of its own.
    @Test("a window title carrying AppleScript syntax is escaped rather than interpolated")
    @MainActor
    func escapesWindowTitle() {
        let script = VSCodeWindowJumper.focusScript(
            applicationPID: editorPID,
            windowTitle: "we\"ird\\path"
        )

        #expect(script?.contains("\"we\\\"ird\\\\path\"") == true)
    }

    @Test("a window title that cannot be quoted safely never reaches AppleScript")
    @MainActor
    func rejectsUnquotableWindowTitle() {
        #expect(VSCodeWindowJumper.focusScript(applicationPID: editorPID, windowTitle: "") == nil)
        #expect(
            VSCodeWindowJumper.focusScript(applicationPID: editorPID, windowTitle: "a\nb") == nil)
    }

    @Test("a title names the workspace it ends with, with or without an editor in front")
    @MainActor
    func recognisesTitlesNamingAWorkspace() {
        #expect(VSCodeWindowJumper.windowTitle("● main.swift — agent-notch", names: "agent-notch"))
        #expect(VSCodeWindowJumper.windowTitle("agent-notch", names: "agent-notch"))
        #expect(VSCodeWindowJumper.windowTitle("agent-notch — docs", names: "agent-notch") == false)
    }

    /// The separator is an ordinary run of characters a folder name may contain.
    @Test("a workspace whose own name contains the separator is matched in one piece")
    @MainActor
    func matchesAWorkspaceNamedLikeATitle() {
        let title = VSCodeWindowJumper.windowTitle(
            forWorkingDirectory: "/Users/me/foo — bar",
            titles: ["main.swift — foo — bar", "tmp"]
        )

        #expect(title == "main.swift — foo — bar")
    }

    @Test("the window whose root is a component of the working directory is the destination")
    @MainActor
    func resolvesWindowFromWorkspaceRoot() {
        let title = VSCodeWindowJumper.windowTitle(
            forWorkingDirectory: "/Users/me/projects/agent-notch",
            titles: ["tmp", "Release Notes — agent-notch", "notes — journal"]
        )

        #expect(title == "Release Notes — agent-notch")
    }

    /// A monorepo run starts inside a package, so the window is titled after an ancestor.
    @Test("a deeper working directory resolves to the window rooted at an ancestor")
    @MainActor
    func resolvesWindowFromAncestorWorkspace() {
        let title = VSCodeWindowJumper.windowTitle(
            forWorkingDirectory: "/Users/me/agent-notch/packages/core",
            titles: ["agent-notch", "tmp"]
        )

        #expect(title == "agent-notch")
    }

    /// Raising the wrong window is worse than raising none: the caller still activates the editor.
    @Test("a working directory that answers to two windows resolves to neither")
    @MainActor
    func refusesAnAmbiguousWorkspace() {
        let title = VSCodeWindowJumper.windowTitle(
            forWorkingDirectory: "/Users/me/agent-notch/packages/core",
            titles: ["agent-notch", "core", "tmp"]
        )

        #expect(title == nil)
    }

    /// `contains` would have matched `core` here, and on any window rooted at `core-utils`.
    @Test("a window root is matched whole rather than as a substring")
    @MainActor
    func matchesWholeComponentsOnly() {
        #expect(
            VSCodeWindowJumper.windowTitle(
                forWorkingDirectory: "/Users/me/agent-notch",
                titles: ["agent-notch-docs", "notch"]
            ) == nil)
    }

    @Test("the trailing newline of the listing leaves no empty title behind")
    @MainActor
    func parsesWindowTitleListing() {
        #expect(
            VSCodeWindowJumper.windowTitles(fromScriptResult: "agent-notch\ntmp\n")
                == ["agent-notch", "tmp"])
        #expect(VSCodeWindowJumper.windowTitles(fromScriptResult: "").isEmpty)
    }

    @Test("only the deepest few path components can name the workspace")
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

    @Test("the listing names the window, and the raise that follows names it back")
    @MainActor
    func raisesTheResolvedWindow() {
        var raised: String?

        let focused = VSCodeWindowJumper.focusWindow(
            forProcessTree: 500,
            applicationPID: editorPID,
            environmentOf: { $0 == 500 ? ["PWD": "/Users/me/projects/agent-notch"] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: { script in
                if script.contains("AXRaise") {
                    raised = script
                    return ""
                }
                return "tmp\nmain.swift — agent-notch\n"
            }
        )

        #expect(focused)
        #expect(raised?.contains("\"main.swift — agent-notch\"") == true)
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
            runScript: { script in
                if script.contains("AXRaise") {
                    Issue.record("raised a window the workspace did not name")
                    return ""
                }
                return "tmp\n"
            }
        )

        #expect(focused == false)
    }

    /// The editor can close a window between the listing and the raise.
    @Test("a raise the editor refuses is reported as a failure")
    @MainActor
    func reportsFailureWhenTheRaiseDoesNotApply() {
        let focused = VSCodeWindowJumper.focusWindow(
            forProcessTree: 500,
            applicationPID: editorPID,
            environmentOf: { $0 == 500 ? ["PWD": "/Users/me/agent-notch"] : nil },
            parentOf: { _ in 1 },
            isAutomationPermitted: { true },
            runScript: { script in script.contains("AXRaise") ? nil : "agent-notch\n" }
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
                return ""
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
                return ""
            }
        )

        #expect(focused == false)
    }
}
