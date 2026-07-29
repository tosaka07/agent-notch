import Foundation
import Testing

@testable import AgentNotch

@Suite("Process environment reading")
struct ProcessEnvironmentTests {
    /// Builds a block in the layout `KERN_PROCARGS2` returns.
    private func makeProcessArguments(
        executablePath: String = "/usr/bin/node",
        arguments: [String],
        environment: [String],
        alignmentPadding: Int = 3,
        terminated: Bool = false
    ) -> Data {
        var data = Data()
        var count = Int32(arguments.count)
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array(executablePath.utf8))
        data.append(0)
        data.append(contentsOf: Array(repeating: UInt8(0), count: alignmentPadding))
        for entry in arguments + environment {
            data.append(contentsOf: Array(entry.utf8))
            data.append(0)
        }
        if terminated {
            data.append(0)
            data.append(contentsOf: Array("SHOULD_NOT_BE_READ=1".utf8))
            data.append(0)
        }
        return data
    }

    @Test("variables are read as key and value")
    func readsVariables() {
        let parsed = ProcessEnvironment.parse(
            processArguments: makeProcessArguments(
                arguments: ["node", "claude"],
                environment: ["TERM=xterm-256color", "CMUX_SURFACE_ID=370E71D2"]
            )
        )

        #expect(parsed?["TERM"] == "xterm-256color")
        #expect(parsed?["CMUX_SURFACE_ID"] == "370E71D2")
        #expect(parsed?.count == 2)
    }

    /// The reason this reads the raw block instead of `ps eww`: there the arguments and the
    /// environment share one line, so a prompt shaped like a variable is indistinguishable from one.
    @Test("an argument shaped like a variable is not read as one")
    func ignoresArgumentsThatLookLikeVariables() {
        let parsed = ProcessEnvironment.parse(
            processArguments: makeProcessArguments(
                arguments: ["claude", "-p", "set CMUX_SURFACE_ID=00000000-0000-0000-0000-000000000000"],
                environment: ["CMUX_SURFACE_ID=370E71D2"]
            )
        )

        #expect(parsed?["CMUX_SURFACE_ID"] == "370E71D2")
        #expect(parsed?.count == 1)
    }

    @Test("a value keeps the separators inside it")
    func keepsSeparatorsInValues() {
        let parsed = ProcessEnvironment.parse(
            processArguments: makeProcessArguments(
                arguments: ["node"],
                environment: ["CMUX_TMUX_SYNC_KEYS=A=1,B=2"]
            )
        )

        #expect(parsed?["CMUX_TMUX_SYNC_KEYS"] == "A=1,B=2")
    }

    @Test("an entry without a separator is skipped")
    func skipsEntriesWithoutSeparator() {
        let parsed = ProcessEnvironment.parse(
            processArguments: makeProcessArguments(
                arguments: ["node"],
                environment: ["MALFORMED", "TERM=dumb"]
            )
        )

        #expect(parsed == ["TERM": "dumb"])
    }

    @Test("an empty entry closes the block")
    func stopsAtEmptyEntry() {
        let parsed = ProcessEnvironment.parse(
            processArguments: makeProcessArguments(
                arguments: ["node"],
                environment: ["TERM=dumb"],
                terminated: true
            )
        )

        #expect(parsed == ["TERM": "dumb"])
    }

    @Test("a block whose executable path needs no padding still parses")
    func parsesWithoutAlignmentPadding() {
        let parsed = ProcessEnvironment.parse(
            processArguments: makeProcessArguments(
                arguments: ["node"],
                environment: ["TERM=dumb"],
                alignmentPadding: 0
            )
        )

        #expect(parsed == ["TERM": "dumb"])
    }

    @Test("a process with no environment parses to an empty set of variables")
    func parsesEmptyEnvironment() {
        let parsed = ProcessEnvironment.parse(
            processArguments: makeProcessArguments(arguments: ["node"], environment: [])
        )

        #expect(parsed == [:])
    }

    @Test("a block too short to hold a count is rejected")
    func rejectsTruncatedBlock() {
        #expect(ProcessEnvironment.parse(processArguments: Data()) == nil)
        #expect(ProcessEnvironment.parse(processArguments: Data([0, 0, 0, 0])) == nil)
    }

    /// The environment of this very process is the one case that can be read for real.
    @Test("the environment of the running process is readable")
    func readsOwnEnvironment() {
        let parsed = ProcessEnvironment.environment(ofPID: ProcessInfo.processInfo.processIdentifier)

        #expect(parsed?["PATH"] == ProcessInfo.processInfo.environment["PATH"])
    }
}
