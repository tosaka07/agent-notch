import Foundation

#if canImport(Security)
    import Security
#endif

/// Claude Code's OAuth credentials.
///
/// The token lives in `accessToken` but must **never** be logged; `CustomStringConvertible`
/// is deliberately not implemented.
public struct ClaudeCredentials: Sendable, Equatable {
    public let accessToken: String
    /// Token expiry, or `nil` if the source does not provide it.
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// Whether the token has expired. An unknown expiry (`nil`) never counts as expired.
    /// Treats the token as expired `leeway` seconds early to avoid a 401 right at the boundary.
    public func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// **Read-only** access to Claude Code's OAuth access token.
///
/// # Why the Keychain is not read directly
///
/// Claude Code creates its Keychain item by spawning `/usr/bin/security add-generic-password`.
/// The item's ACL therefore trusts **only `/usr/bin/security`** — neither Claude Code itself nor
/// Agent Notch is on it. That asymmetry has consequences:
///
/// - Reading the **password data** via `SecItemCopyMatching` (`kSecReturnData: true`) fails the
///   ACL check and raises the "another application wants to access your keychain item" dialog.
///   Choosing "Always Allow" does not help for long, because the grant is keyed to the binary's
///   signature, and a development build's ad-hoc signature changes on every `swift build` — which
///   is exactly why the prompt reappears periodically.
/// - Reading the same item **through the `/usr/bin/security` subprocess** raises no dialog, since
///   the ACL already trusts that binary.
/// - An **attributes-only** `SecItemCopyMatching` (without `kSecReturnData`) does not consult the
///   ACL and raises no dialog. It is used solely to enumerate service names.
///
/// The lookup order is therefore `~/.claude/.credentials.json`, then the `/usr/bin/security`
/// subprocess. **Data is never read through `SecItemCopyMatching`.**
///
/// # Why preferring `.credentials.json` is acceptable
///
/// That file is plaintext JSON under the same user's home directory, written by Claude Code itself
/// with mode 0600 (owner-readable only). Agent Notch runs with the same user privileges, so reading
/// it grants no access the process did not already have. This store is also **read-only**: it never
/// writes, deletes, or forwards the credentials to another process, and never puts the token in a
/// log or the UI. On macOS the file usually does not exist and the Keychain is authoritative, so in
/// practice most setups take the `security` path.
public enum ClaudeCredentialsStore {
    /// Service name used by Claude Code v2.1.51 and earlier.
    static let legacyServiceName = "Claude Code-credentials"
    /// v2.1.52+ uses `Claude Code-credentials-<hash>`.
    static let serviceNamePrefix = "Claude Code-credentials"

    /// Cap so a hung `security` subprocess cannot stall the caller.
    private static let commandTimeout: TimeInterval = 5

    // MARK: - Public

    /// Loads the credentials, quietly returning `nil` when unavailable.
    public static func load() -> ClaudeCredentials? {
        if let creds = loadFromFile() {
            Log.hooks.debug("Claude credentials: loaded from ~/.claude/.credentials.json")
            return creds
        }
        if let creds = loadFromSecurityCommand() {
            Log.hooks.debug("Claude credentials: loaded via /usr/bin/security")
            return creds
        }
        Log.hooks.debug("Claude credentials: not found")
        return nil
    }

    // MARK: - Sources

    private static func loadFromFile() -> ClaudeCredentials? {
        let path = NSHomeDirectory() + "/.claude/.credentials.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return parse(data: data)
    }

    /// Reads the password itself with `/usr/bin/security find-generic-password -w`.
    /// No authorization dialog appears, because the ACL trusts `/usr/bin/security`.
    private static func loadFromSecurityCommand() -> ClaudeCredentials? {
        guard let service = resolveServiceName() else { return nil }
        guard
            let output = runSecurity(arguments: [
                "find-generic-password",
                "-s", service,
                "-a", NSUserName(),
                "-w",
            ])
        else { return nil }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return parse(data: data)
    }

    // MARK: - Service name resolution

    /// Determines which `Claude Code-credentials*` service name exists in the Keychain.
    ///
    /// This is an attributes-only query, so it does not consult the ACL and raises no dialog.
    /// The unsuffixed name (`Claude Code-credentials`) wins if present; otherwise the
    /// **most recently modified** hashed name is chosen. With several accounts in use
    /// (several `CLAUDE_CONFIG_DIR`s), that means the most recently used account. No exact
    /// matching is attempted.
    static func resolveServiceName() -> String? {
        #if canImport(Security)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let items = result as? [[String: Any]] else { return nil }

            let candidates: [(service: String, modified: Date)] = items.compactMap { item in
                guard let service = item[kSecAttrService as String] as? String,
                    service.hasPrefix(serviceNamePrefix)
                else { return nil }
                let modified = item[kSecAttrModificationDate as String] as? Date ?? .distantPast
                return (service, modified)
            }
            guard !candidates.isEmpty else { return nil }

            if candidates.contains(where: { $0.service == legacyServiceName }) {
                return legacyServiceName
            }
            return candidates.max(by: { $0.modified < $1.modified })?.service
        #else
            return nil
        #endif
    }

    // MARK: - Parsing

    /// The Keychain and the file share one JSON shape:
    /// `{"claudeAiOauth": {"accessToken": ..., "expiresAt": <epoch ms>}}`
    static func parse(data: Data) -> ClaudeCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let container = (json["claudeAiOauth"] as? [String: Any]) ?? json
        guard let token = container["accessToken"] as? String, !token.isEmpty else { return nil }
        return ClaudeCredentials(accessToken: token, expiresAt: expiry(from: container["expiresAt"]))
    }

    /// `expiresAt` holds epoch milliseconds; values in seconds are tolerated too.
    static func expiry(from value: Any?) -> Date? {
        let raw: Double
        switch value {
        case let number as NSNumber: raw = number.doubleValue
        case let string as String:
            guard let parsed = Double(string) else { return nil }
            raw = parsed
        default: return nil
        }
        guard raw > 0 else { return nil }
        // >= 10^12 means milliseconds; the threshold cannot collide with seconds from 2001 onward.
        let seconds = raw >= 1_000_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Subprocess

    /// Launches `/usr/bin/security` directly with an argument array (no shell).
    /// Its stdout carries the token, so it must **never** be logged.
    private static func runSecurity(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            Log.hooks.debug("Claude credentials: failed to launch security: \(error.localizedDescription)")
            return nil
        }

        // Hang guard. The output is far too small to fill the pipe, so draining it after exit is enough.
        let deadline = Date().addingTimeInterval(commandTimeout)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            Log.hooks.debug("Claude credentials: security command timed out")
            return nil
        }

        guard process.terminationStatus == 0 else {
            // 44 = item not found. Other codes are also given up on quietly, without reporting a reason.
            Log.hooks.debug("Claude credentials: security exited with \(process.terminationStatus)")
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
