import Foundation
import Testing

@testable import AgentNotch

@Suite("App relaunch")
@MainActor
struct AppRelauncherTests {
    @Test("The helper is scheduled before the current app terminates")
    func helperStartsBeforeTermination() {
        let applicationURL = URL(fileURLWithPath: "/Applications/Agent Notch.app")
        var helperURL: URL?
        var helperArguments: [String] = []
        var didLaunchHelper = false
        var didTerminate = false
        var didReportFailure = false

        AppRelauncher.relaunch(
            applicationURL: applicationURL,
            processID: 42,
            launchHelper: { url, arguments in
                helperURL = url
                helperArguments = arguments
                didLaunchHelper = true
                #expect(didTerminate == false)
            },
            terminate: { didTerminate = true },
            onFailure: { didReportFailure = true }
        )

        #expect(helperURL?.path == "/bin/sh")
        #expect(didLaunchHelper)
        #expect(didTerminate)
        #expect(didReportFailure == false)
        #expect(helperArguments.suffix(3) == ["agent-notch-relaunch", "42", applicationURL.path])
        #expect(helperArguments[1].contains(#"kill -0 "$1""#))
        #expect(helperArguments[1].contains(#"/usr/bin/open -n "$2""#))
        #expect(helperArguments[1].contains(applicationURL.path) == false)
    }

    @Test("A failed helper launch keeps the current app running")
    func failedHelperKeepsCurrentAppRunning() {
        var didTerminate = false
        var didReportFailure = false

        AppRelauncher.relaunch(
            launchHelper: { _, _ in throw RelaunchTestError.launchFailed },
            terminate: { didTerminate = true },
            onFailure: { didReportFailure = true }
        )

        #expect(didTerminate == false)
        #expect(didReportFailure)
    }

    @Test("A direct debug build relaunches its executable")
    func directBuildRelaunchesExecutable() throws {
        let executableURL = URL(fileURLWithPath: "/tmp/debug/AgentNotch")
        let arguments = try #require(
            AppRelauncher.helperArguments(
                applicationURL: URL(fileURLWithPath: "/tmp/debug"),
                executableURL: executableURL,
                processID: 7
            )
        )

        #expect(arguments.suffix(3) == ["agent-notch-relaunch", "7", executableURL.path])
        #expect(arguments[1].contains(#"exec "$2""#))
        #expect(arguments[1].contains("/usr/bin/open") == false)
    }

    @Test("No launch target keeps the current app running")
    func missingLaunchTargetKeepsCurrentAppRunning() {
        var didLaunchHelper = false
        var didTerminate = false
        var didReportFailure = false

        AppRelauncher.relaunch(
            applicationURL: URL(fileURLWithPath: "/tmp/debug"),
            executableURL: nil,
            launchHelper: { _, _ in didLaunchHelper = true },
            terminate: { didTerminate = true },
            onFailure: { didReportFailure = true }
        )

        #expect(didLaunchHelper == false)
        #expect(didTerminate == false)
        #expect(didReportFailure)
    }
}

private enum RelaunchTestError: Error {
    case launchFailed
}
