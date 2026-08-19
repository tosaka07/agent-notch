import Foundation

/// Codex's runtime decision for the Agent Notch command hooks.
///
/// This is deliberately separate from `HookInstaller.isInstalled`: a hook can be present in
/// `hooks.json` while Codex skips it because its exact definition changed after the user trusted
/// it.
public enum CodexHookTrustState: Equatable, Sendable {
    case trusted
    case needsReview
    case disabled
    case notFound
    case unavailable
}

/// Reads Codex's own effective hook metadata through the official App Server `hooks/list` method.
///
/// Agent Notch never writes Codex's trust state. Trust is a security boundary owned by Codex and
/// the user; this client only makes a skipped hook visible in Agent Notch's Settings.
public actor CodexHookTrustClient {
    public static let shared = CodexHookTrustClient()

    public init() {}

    public func inspect(
        expectedCommand: String,
        cwd: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> CodexHookTrustState {
        guard let executableURL = Self.resolveExecutable() else {
            Log.hooks.debug("Codex hook trust inspection skipped: executable not found")
            return .unavailable
        }

        do {
            let response = try await CodexAppServerProcess(
                executableURL: executableURL,
                arguments: ["app-server", "--stdio"],
                timeout: 5,
                requestMethod: "hooks/list",
                requestParams: ["cwds": [cwd.standardizedFileURL.path]]
            ).request()
            return try CodexHookTrustParser.parseResponse(
                response,
                expectedCommand: expectedCommand
            )
        } catch {
            Log.hooks.debug(
                "Codex hook trust inspection unavailable: \(error.localizedDescription)"
            )
            return .unavailable
        }
    }

    /// Prefer the executable inside the desktop app because it owns the sessions whose hook
    /// state Agent Notch is diagnosing. Fall back to the user's CLI for CLI-only installations.
    private static func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["AGENT_NOTCH_CODEX_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let appRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
        ]
        let appNames = ["ChatGPT.app", "Codex.app"]
        for root in appRoots {
            for appName in appNames {
                let candidate =
                    root
                    .appendingPathComponent(appName, isDirectory: true)
                    .appendingPathComponent("Contents/Resources/codex")
                    .standardizedFileURL
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return CodexExecutableResolver.resolve(
            environment: environment,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
    }
}

enum CodexHookTrustParser {
    static func parseResponse(
        _ data: Data,
        expectedCommand: String
    ) throws -> CodexHookTrustState {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let error = response.error {
            throw CodexAppServerError.rpc(error.message)
        }
        guard let result = response.result else {
            throw CodexAppServerError.invalidResponse
        }

        let matchingHooks = result.data
            .flatMap(\.hooks)
            .filter { $0.command == expectedCommand }
        guard !matchingHooks.isEmpty else { return .notFound }

        // One disabled event is enough to make the integration incomplete even if the other ten
        // events remain trusted.
        if matchingHooks.contains(where: { !$0.enabled }) {
            return .disabled
        }
        if matchingHooks.contains(where: \.requiresReview) {
            return .needsReview
        }
        if matchingHooks.allSatisfy(\.isTrusted) {
            return .trusted
        }
        return .unavailable
    }

    private struct Response: Decodable {
        let result: Result?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let message: String
    }

    private struct Result: Decodable {
        let data: [HookList]
    }

    private struct HookList: Decodable {
        let hooks: [Hook]
    }

    private struct Hook: Decodable {
        let command: String?
        let enabled: Bool
        let isManaged: Bool
        let trustStatus: String?

        var requiresReview: Bool {
            guard !isManaged else { return false }
            return trustStatus == "modified" || trustStatus == "untrusted"
        }

        var isTrusted: Bool {
            isManaged || trustStatus == "trusted" || trustStatus == "managed"
        }
    }
}
