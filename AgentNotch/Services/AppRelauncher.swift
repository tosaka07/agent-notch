import AgentNotchCore
import AppKit

/// Schedules a replacement app instance and then terminates the current one.
///
/// The two instances must not overlap. Both own the same Unix socket, so a new
/// instance starting before the old one finishes could leave the replacement
/// without a reachable socket. A tiny helper waits for this process to exit
/// before asking Launch Services to open the app again.
@MainActor
enum AppRelauncher {
    typealias HelperLauncher = @MainActor (URL, [String]) throws -> Void

    private static let helperURL = URL(fileURLWithPath: "/bin/sh")

    static func relaunch(
        applicationURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        launchHelper: HelperLauncher = runHelper,
        terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
        onFailure: @escaping @MainActor () -> Void = {}
    ) {
        guard
            let arguments = helperArguments(
                applicationURL: applicationURL,
                executableURL: executableURL,
                processID: processID
            )
        else {
            Log.panel.error("Agent Notch relaunch failed: no launchable app or executable")
            onFailure()
            return
        }

        do {
            try launchHelper(helperURL, arguments)
            terminate()
        } catch {
            Log.panel.error("Agent Notch relaunch failed: \(error.localizedDescription)")
            onFailure()
        }
    }

    /// The app URL and PID are positional shell arguments, never interpolated
    /// into the command, so paths containing spaces or shell syntax stay data.
    static func helperArguments(
        applicationURL: URL,
        executableURL: URL?,
        processID: Int32
    ) -> [String]? {
        let command: String
        let launchTarget: String
        if applicationURL.pathExtension.lowercased() == "app" {
            command =
                #"while kill -0 "$1" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open -n "$2""#
            launchTarget = applicationURL.path
        } else if let executableURL {
            // `swift run` and direct debug builds do not live inside an app
            // bundle. Relaunch the executable itself in that environment.
            command =
                #"while kill -0 "$1" 2>/dev/null; do sleep 0.1; done; exec "$2""#
            launchTarget = executableURL.path
        } else {
            return nil
        }

        return [
            "-c",
            command,
            "agent-notch-relaunch",
            String(processID),
            launchTarget,
        ]
    }

    private static func runHelper(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
    }
}
