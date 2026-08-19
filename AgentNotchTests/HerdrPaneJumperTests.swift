import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("herdr pane selection")
struct HerdrPaneJumperTests {
    private let socketPath = "/Users/tester/.config/herdr/herdr.sock"

    // MARK: - Locating the pane

    @Test("the pane comes from the session's own process when it has one")
    func readsPaneFromSessionProcess() {
        let location = HerdrPaneJumper.location(
            forProcessTree: 500,
            environmentOf: {
                $0 == 500
                    ? ["HERDR_PANE_ID": "w6:p2", "HERDR_SOCKET_PATH": socketPath]
                    : nil
            },
            parentOf: { _ in
                Issue.record("walked past a process that had the variable")
                return 1
            }
        )

        #expect(location == HerdrPaneJumper.Location(paneId: "w6:p2", socketPath: socketPath))
    }

    /// A tmux client, or a process picked off the TTY, can sit between the session and the pane shell.
    @Test("the pane is found on an ancestor when the anchor does not carry it")
    func readsPaneFromAncestor() {
        let environments: [Int32: [String: String]] = [
            500: ["TERM": "xterm-256color"],
            400: ["HERDR_PANE_ID": "w1:pD", "HERDR_SOCKET_PATH": socketPath],
        ]

        let location = HerdrPaneJumper.location(
            forProcessTree: 500,
            environmentOf: { environments[$0] },
            parentOf: { $0 == 500 ? 400 : 1 }
        )

        #expect(location?.paneId == "w1:pD")
    }

    /// herdr always injects the socket path, but a pane whose environment was inherited through
    /// something that dropped it still belongs to the session every plain `herdr` run attaches to.
    @Test("a missing socket variable falls back to the unnamed session's socket")
    func fallsBackToDefaultSocket() {
        let location = HerdrPaneJumper.location(
            forProcessTree: 500,
            environmentOf: { $0 == 500 ? ["HERDR_PANE_ID": "w6:p2"] : nil },
            parentOf: { _ in 1 }
        )

        #expect(location?.socketPath == HerdrPaneJumper.defaultSocketPath)
    }

    @Test("a process tree outside herdr resolves to nothing")
    func resolvesNothingOutsideHerdr() {
        let location = HerdrPaneJumper.location(
            forProcessTree: 500,
            environmentOf: { _ in ["TERM": "xterm-ghostty"] },
            parentOf: { $0 == 500 ? 400 : 1 }
        )

        #expect(location == nil)
    }

    @Test("a pane variable that is not a pane identifier is ignored, and the walk goes on")
    func ignoresUnusablePaneIdentifiers() {
        let environments: [Int32: [String: String]] = [
            500: ["HERDR_PANE_ID": ""],
            400: ["HERDR_PANE_ID": "not-a-pane"],
            300: ["HERDR_PANE_ID": "w2:p7", "HERDR_SOCKET_PATH": socketPath],
        ]

        let location = HerdrPaneJumper.location(
            forProcessTree: 500,
            environmentOf: { environments[$0] },
            parentOf: { $0 == 500 ? 400 : ($0 == 400 ? 300 : 1) }
        )

        #expect(location?.paneId == "w2:p7")
    }

    @Test("the walk stops at the depth limit instead of following a cycle")
    func stopsAtDepthLimit() {
        var visited = 0

        let location = HerdrPaneJumper.location(
            forProcessTree: 500,
            environmentOf: { _ in
                visited += 1
                return [:]
            },
            parentOf: { $0 == 500 ? 400 : 500 },
            maximumDepth: 4
        )

        #expect(location == nil)
        #expect(visited == 4)
    }

    @Test("herdr's own identifiers are accepted and nothing else is")
    func recognisesPaneIdentifiers() {
        #expect(HerdrPaneJumper.isPaneIdentifier("w6:p2"))
        #expect(HerdrPaneJumper.isPaneIdentifier("w12:pD"))
        #expect(HerdrPaneJumper.isPaneIdentifier("w6:p2 w6:p3") == false)
        #expect(HerdrPaneJumper.isPaneIdentifier("w6:t2") == false)
        #expect(HerdrPaneJumper.isPaneIdentifier("w6") == false)
        #expect(HerdrPaneJumper.isPaneIdentifier("w:p") == false)
        #expect(HerdrPaneJumper.isPaneIdentifier("") == false)
    }

    // MARK: - Driving herdr

    @Test("focusing addresses the resolved pane over the session's own socket")
    func focusesResolvedPane() {
        var calls: [(method: String, params: [String: String], socketPath: String)] = []

        let didFocus = HerdrPaneJumper.focusPane(
            HerdrPaneJumper.Location(paneId: "w6:p2", socketPath: socketPath),
            call: { method, params, path in
                calls.append((method, params, path))
                return .result(["type": "pane_info"])
            }
        )

        #expect(didFocus)
        #expect(calls.count == 1)
        #expect(calls.first?.method == "pane.focus")
        #expect(calls.first?.params == ["pane_id": "w6:p2"])
        #expect(calls.first?.socketPath == socketPath)
    }

    /// `pane.focus` is in the shipped schema but not in the published method table, so a build that
    /// does not know it must still be able to focus the pane.
    @Test("a herdr that does not know pane.focus is asked through agent.focus")
    func fallsBackToAgentFocus() {
        var methods: [String] = []

        let didFocus = HerdrPaneJumper.focusPane(
            HerdrPaneJumper.Location(paneId: "w6:p2", socketPath: socketPath),
            call: { method, params, _ in
                methods.append(method)
                if method == "pane.focus" {
                    return .failure(code: "unknown_method", message: "pane.focus")
                }
                #expect(params == ["target": "w6:p2"])
                return .result(["type": "agent_info"])
            }
        )

        #expect(didFocus)
        #expect(methods == ["pane.focus", "agent.focus"])
    }

    @Test("a pane nothing will focus reports no focus, leaving a plain activation")
    func reportsRefusedFocus() {
        let didFocus = HerdrPaneJumper.focusPane(
            HerdrPaneJumper.Location(paneId: "w6:p2", socketPath: socketPath),
            call: { _, _, _ in nil }
        )

        #expect(didFocus == false)
    }

    @Test("a pane herdr no longer holds is not a destination")
    func stalePaneDoesNotExist() {
        let location = HerdrPaneJumper.Location(paneId: "w6:p2", socketPath: socketPath)

        #expect(
            HerdrPaneJumper.paneExists(
                location,
                call: { _, _, _ in .result(["type": "pane_info"]) }
            )
        )
        #expect(
            HerdrPaneJumper.paneExists(
                location,
                call: { _, _, _ in .failure(code: "not_found", message: "pane not found") }
            ) == false
        )
        #expect(HerdrPaneJumper.paneExists(location, call: { _, _, _ in nil }) == false)
    }

    // MARK: - Finding the client

    @Test("a socket path names the session it serves")
    func readsSessionNameFromSocketPath() {
        #expect(HerdrPaneJumper.sessionName(forSocketPath: socketPath) == nil)
        #expect(
            HerdrPaneJumper.sessionName(
                forSocketPath: "/Users/tester/.config/herdr/sessions/work/herdr.sock"
            ) == "work"
        )
    }

    @Test("a client's session is read from its flag, its subcommand, or its environment")
    func readsSessionNameFromClient() {
        #expect(HerdrPaneJumper.clientSessionName(arguments: "herdr", environment: [:]) == nil)
        #expect(
            HerdrPaneJumper.clientSessionName(arguments: "herdr --session work", environment: nil)
                == "work"
        )
        #expect(
            HerdrPaneJumper.clientSessionName(
                arguments: "herdr session attach work",
                environment: nil
            ) == "work"
        )
        #expect(
            HerdrPaneJumper.clientSessionName(
                arguments: "herdr",
                environment: ["HERDR_SESSION": "work"]
            ) == "work"
        )
    }

    @Test("the server and remote attachments are not clients to activate")
    func classifiesServerAndRemote() {
        #expect(HerdrPaneJumper.isServer(arguments: "/opt/bin/herdr server"))
        #expect(HerdrPaneJumper.isServer(arguments: "herdr") == false)
        #expect(HerdrPaneJumper.isRemote(arguments: "herdr --remote workbox"))
        #expect(HerdrPaneJumper.isRemote(arguments: "herdr") == false)
    }

    @Test("only the clients of this session are offered, newest first")
    func picksClientsOfTheSameSession() {
        let processes = [
            HerdrPaneJumper.RunningProcess(pid: 100, parentPID: 1, executablePath: "/bin/zsh"),
            HerdrPaneJumper.RunningProcess(pid: 200, parentPID: 1, executablePath: "/opt/bin/herdr"),
            HerdrPaneJumper.RunningProcess(pid: 300, parentPID: 1, executablePath: "/opt/bin/herdr"),
            HerdrPaneJumper.RunningProcess(pid: 400, parentPID: 1, executablePath: "/opt/bin/herdr"),
            HerdrPaneJumper.RunningProcess(pid: 500, parentPID: 1, executablePath: "/opt/bin/herdr"),
        ]
        let arguments: [Int32: String] = [
            200: "herdr server",
            300: "herdr",
            400: "herdr --session work",
            500: "herdr",
        ]

        let clients = HerdrPaneJumper.clientPIDs(
            forSocketPath: socketPath,
            processes: { processes },
            argumentsOf: { arguments[$0] ?? "" },
            environmentOf: { _ in [:] }
        )

        #expect(clients == [500, 300])
    }

    @Test("a named session is served by the client started against that name")
    func picksNamedSessionClient() {
        let processes = [
            HerdrPaneJumper.RunningProcess(pid: 300, parentPID: 1, executablePath: "/opt/bin/herdr"),
            HerdrPaneJumper.RunningProcess(pid: 400, parentPID: 1, executablePath: "/opt/bin/herdr"),
        ]
        let arguments: [Int32: String] = [300: "herdr", 400: "herdr --session work"]

        let clients = HerdrPaneJumper.clientPIDs(
            forSocketPath: "/Users/tester/.config/herdr/sessions/work/herdr.sock",
            processes: { processes },
            argumentsOf: { arguments[$0] ?? "" },
            environmentOf: { _ in [:] }
        )

        #expect(clients == [400])
    }
}
