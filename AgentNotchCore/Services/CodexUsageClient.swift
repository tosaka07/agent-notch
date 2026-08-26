import Foundation

/// Fetches Codex usage through one small interface.
///
/// Codex App Server is authoritative because it reports usage-based allowances
/// that rollout JSONL files may omit. The rollout parser is retained as a
/// compatibility adapter for missing, old, or temporarily failing Codex CLIs.
public actor CodexUsageClient {
    public static let shared = CodexUsageClient()

    typealias AppServerFetch = @Sendable () async throws -> CodexUsageSnapshot?
    typealias RolloutFetch = @Sendable () -> CodexUsageSnapshot?

    private let fetchFromAppServer: AppServerFetch
    private let fetchFromRollout: RolloutFetch

    public init() {
        fetchFromAppServer = {
            try await CodexAppServerUsageProvider.fetchUsage()
        }
        fetchFromRollout = {
            CodexUsageParser.latestSnapshot()
        }
    }

    init(
        fetchFromAppServer: @escaping AppServerFetch,
        fetchFromRollout: @escaping RolloutFetch
    ) {
        self.fetchFromAppServer = fetchFromAppServer
        self.fetchFromRollout = fetchFromRollout
    }

    /// Convenience for callers that only care whether usage arrived.
    public func fetchUsage() async -> CodexUsageSnapshot? {
        guard case .success(let snapshot) = await fetch() else { return nil }
        return snapshot
    }

    public func fetch() async -> CodexUsageFetch {
        // Both routes below are Codex's: its app server process and its rollout files.
        guard CodexAccess.isAllowed else {
            Log.usage.debug("Codex usage skipped: the Codex integration is off")
            return .unavailable(.integrationDisabled)
        }
        // Distinguishes "the app server could not be reached at all" from "it answered but had
        // no window to report", so the UI can name the right cause.
        var appServerFailed = false
        do {
            if let snapshot = try await fetchFromAppServer() {
                if snapshot.primary != nil
                    || snapshot.secondary != nil
                    || snapshot.individualLimit != nil
                {
                    return .success(snapshot)
                }

                // A version-skewed App Server can still return account metadata
                // without a usable limit. Prefer a real rollout window when one
                // exists, but retain the metadata-only response otherwise.
                return .success(fetchFromRollout() ?? snapshot)
            }
        } catch {
            Log.usage.debug("Codex usage: App Server unavailable: \(error.localizedDescription)")
            appServerFailed = true
        }

        if let rollout = fetchFromRollout() {
            return .success(rollout)
        }
        return .unavailable(appServerFailed ? .agentUnreachable : .noLimits)
    }
}

/// Outcome of one usage fetch: either a snapshot, or the reason there is none.
public enum CodexUsageFetch: Sendable, Equatable {
    case success(CodexUsageSnapshot)
    case unavailable(UsageUnavailableReason)
}

// MARK: - App Server adapter

enum CodexAppServerUsageProvider {
    static func fetchUsage() async throws -> CodexUsageSnapshot? {
        guard let executableURL = CodexExecutableResolver.resolve() else {
            throw CodexAppServerError.executableNotFound
        }

        let response = try await CodexAppServerProcess(
            executableURL: executableURL,
            arguments: ["app-server", "--stdio"],
            timeout: 8,
            requestMethod: "account/rateLimits/read",
            requestParams: NSNull()
        ).request()
        return try CodexAppServerUsageParser.parseResponse(response)
    }
}

enum CodexAppServerUsageParser {
    static func parseResponse(_ data: Data) throws -> CodexUsageSnapshot? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let error = response.error {
            throw CodexAppServerError.rpc(error.message)
        }
        guard let result = response.result else {
            throw CodexAppServerError.invalidResponse
        }

        let raw = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
        guard let raw else { return nil }

        let primary = raw.primary?.usageWindow
        let secondary = raw.secondary?.usageWindow
        let individualLimit = raw.individualLimit?.spendLimit
        guard
            primary != nil
                || secondary != nil
                || individualLimit != nil
                || raw.planType != nil
        else { return nil }

        return CodexUsageSnapshot(
            primary: primary,
            secondary: secondary,
            planType: raw.planType,
            individualLimit: individualLimit
        )
    }

    private struct Response: Decodable {
        let result: Result?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let message: String
    }

    private struct Result: Decodable {
        let rateLimits: RateLimitSnapshot?
        let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    }

    private struct RateLimitSnapshot: Decodable {
        let primary: RateLimitWindow?
        let secondary: RateLimitWindow?
        let individualLimit: SpendControlLimit?
        let planType: String?
    }

    private struct RateLimitWindow: Decodable {
        let usedPercent: FlexibleDouble?
        let resetsAt: FlexibleDouble?

        var usageWindow: UsageWindow? {
            guard let usedPercent else { return nil }
            return UsageWindow(
                usedPercent: usedPercent.value,
                resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0.value) }
            )
        }
    }

    private struct SpendControlLimit: Decodable {
        let limit: FlexibleDecimal?
        let used: FlexibleDecimal?
        let remainingPercent: FlexibleDouble?
        let resetsAt: FlexibleDouble?

        var spendLimit: CodexSpendLimit? {
            guard let limit, let used, let remainingPercent, let resetsAt else {
                return nil
            }
            return CodexSpendLimit(
                used: used.value,
                limit: limit.value,
                remainingPercent: remainingPercent.value,
                resetsAt: Date(timeIntervalSince1970: resetsAt.value)
            )
        }
    }

    private struct FlexibleDouble: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self.value = value
                return
            }
            if let raw = try? container.decode(String.self), let value = Double(raw) {
                self.value = value
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a number or numeric string"
            )
        }
    }

    private struct FlexibleDecimal: Decodable {
        let value: Decimal

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self),
                let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
            {
                self.value = value
                return
            }
            if let value = try? container.decode(Decimal.self) {
                self.value = value
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal number or numeric string"
            )
        }
    }
}

// MARK: - Executable discovery

public enum CodexExecutableResolver {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []

        if let override = environment["AGENT_NOTCH_CODEX_PATH"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        candidates.append(contentsOf: pathDirectories.map { $0.appendingPathComponent("codex") })

        var knownDirectories = [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".volta/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".bun/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".asdf/shims", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/pnpm", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/run/current-system/sw/bin", isDirectory: true),
        ]
        if let user = environment["USER"], !user.isEmpty {
            knownDirectories.append(
                URL(fileURLWithPath: "/etc/profiles/per-user/\(user)/bin", isDirectory: true)
            )
        }
        candidates.append(contentsOf: knownDirectories.map { $0.appendingPathComponent("codex") })
        let versionedInstallations = [
            (root: ".nvm/versions/node", suffix: "bin/codex"),
            (root: ".local/share/fnm/node-versions", suffix: "installation/bin/codex"),
            (
                root: "Library/Application Support/fnm/node-versions",
                suffix: "installation/bin/codex"
            ),
            (root: ".local/share/mise/installs/node", suffix: "bin/codex"),
            (root: ".asdf/installs/nodejs", suffix: "bin/codex"),
        ]
        for installation in versionedInstallations {
            candidates.append(
                contentsOf: contentsOfVersionedInstallations(
                    at: homeDirectory.appendingPathComponent(
                        installation.root,
                        isDirectory: true
                    ),
                    executableSuffix: installation.suffix,
                    fileManager: fileManager
                )
            )
        }

        var seen = Set<String>()
        return candidates.first { candidate in
            let path = candidate.standardizedFileURL.path
            guard seen.insert(path).inserted else { return false }
            return fileManager.isExecutableFile(atPath: path)
        }?.standardizedFileURL
    }

    private static func contentsOfVersionedInstallations(
        at root: URL,
        executableSuffix: String,
        fileManager: FileManager
    ) -> [URL] {
        let versions =
            (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        return
            versions
            .sorted { lhs, rhs in
                let lhsDate = try? lhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rhsDate = try? rhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                if lhsDate != rhsDate {
                    return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
                }
                return lhs.lastPathComponent > rhs.lastPathComponent
            }
            .map { $0.appendingPathComponent(executableSuffix) }
    }
}

// MARK: - One-shot JSON-RPC process

enum CodexAppServerError: LocalizedError {
    case executableNotFound
    case launch(String)
    case rpc(String)
    case invalidResponse
    case responseTooLarge
    case timedOut
    case terminated(Int32)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex executable was not found"
        case .launch(let message):
            "Codex App Server could not start: \(message)"
        case .rpc(let message):
            "Codex App Server returned an error: \(message)"
        case .invalidResponse:
            "Codex App Server returned an invalid response"
        case .responseTooLarge:
            "Codex App Server response exceeded the size limit"
        case .timedOut:
            "Codex App Server timed out"
        case .terminated(let status):
            "Codex App Server exited with status \(status)"
        }
    }
}

/// Runs one App Server exchange and terminates it after the matching response.
///
/// The state machine waits for initialize response id 1 before announcing
/// `initialized` and sending the configured request as id 2. Notifications and unrelated
/// responses are ignored.
final class CodexAppServerProcess: @unchecked Sendable {
    private enum Phase: Equatable {
        case awaitingInitialization
        case awaitingResponse
    }

    private enum Completion {
        case success(Data)
        case failure(any Error)
    }

    private let executableURL: URL
    private let arguments: [String]
    private let timeout: TimeInterval
    private let requestMethod: String
    private let requestParams: Any
    private let maxBufferedBytes = 1_048_576

    private let lock = NSLock()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var continuation: CheckedContinuation<Data, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var buffer = Data()
    private var phase = Phase.awaitingInitialization
    private var isFinished = false

    init(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        requestMethod: String = "account/rateLimits/read",
        requestParams: Any = NSNull()
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
        self.requestMethod = requestMethod
        self.requestParams = requestParams
    }

    func request() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, any Error>) in
                start(continuation: continuation)
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    /// Kept as the narrow convenience used by existing usage-process tests.
    func requestRateLimits() async throws -> Data {
        try await request()
    }

    private func start(continuation: CheckedContinuation<Data, any Error>) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.receive(handle.availableData)
        }
        process.terminationHandler = { [weak self] process in
            self?.processDidTerminate(status: process.terminationStatus)
        }

        lock.withLock {
            self.process = process
            inputHandle = input.fileHandleForWriting
            outputHandle = output.fileHandleForReading
            self.continuation = continuation
        }

        do {
            try process.run()
            try send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "agent-notch",
                        "title": "Agent Notch",
                        "version": Self.clientVersion,
                    ]
                ],
            ])
            installTimeout()
        } catch {
            finish(.failure(CodexAppServerError.launch(error.localizedDescription)))
        }
    }

    private static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func installTimeout() {
        let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(CodexAppServerError.timedOut))
        }

        let shouldCancel = lock.withLock {
            if isFinished { return true }
            timeoutTask = task
            return false
        }
        if shouldCancel { task.cancel() }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }

        var lines: [Data] = []
        let exceededLimit = lock.withLock {
            guard !isFinished else { return false }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(Data(buffer[..<newline]))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return buffer.count > maxBufferedBytes
        }

        if exceededLimit {
            finish(.failure(CodexAppServerError.responseTooLarge))
            return
        }
        for line in lines where !line.isEmpty {
            processLine(line)
        }
    }

    private func processLine(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let id = (object["id"] as? NSNumber)?.intValue,
            id == 1 || id == 2
        else {
            // Notifications have no id. Malformed and unrelated lines are
            // equally irrelevant to the two outstanding requests.
            return
        }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown JSON-RPC error"
            finish(.failure(CodexAppServerError.rpc(message)))
            return
        }
        guard object["result"] != nil else {
            finish(.failure(CodexAppServerError.invalidResponse))
            return
        }

        if id == 1 {
            let shouldSendRequest = lock.withLock {
                guard !isFinished, phase == .awaitingInitialization else { return false }
                phase = .awaitingResponse
                return true
            }
            guard shouldSendRequest else { return }

            do {
                try send(["method": "initialized", "params": [:]])
                try send(["id": 2, "method": requestMethod, "params": requestParams])
            } catch {
                finish(.failure(CodexAppServerError.rpc(error.localizedDescription)))
            }
            return
        }

        let isExpected = lock.withLock {
            !isFinished && phase == .awaitingResponse
        }
        if isExpected {
            finish(.success(line))
        }
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        guard let handle = lock.withLock({ isFinished ? nil : inputHandle }) else {
            throw CodexAppServerError.invalidResponse
        }
        try handle.write(contentsOf: data)
    }

    private func processDidTerminate(status: Int32) {
        // FileHandle may deliver the final stdout line just after Process posts
        // termination. Give that callback a small turn before reporting EOF.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(CodexAppServerError.terminated(status)))
        }
    }

    private func finish(_ completion: Completion) {
        let resources:
            (
                continuation: CheckedContinuation<Data, any Error>,
                process: Process?,
                input: FileHandle?,
                output: FileHandle?,
                timeout: Task<Void, Never>?
            )? = lock.withLock {
                guard !isFinished, let continuation else { return nil }
                isFinished = true
                self.continuation = nil
                let resources = (
                    continuation,
                    process,
                    inputHandle,
                    outputHandle,
                    timeoutTask
                )
                process = nil
                inputHandle = nil
                outputHandle = nil
                timeoutTask = nil
                return resources
            }

        guard let resources else { return }
        resources.timeout?.cancel()
        resources.output?.readabilityHandler = nil
        try? resources.input?.close()
        if resources.process?.isRunning == true {
            resources.process?.terminate()
        }

        switch completion {
        case .success(let data):
            resources.continuation.resume(returning: data)
        case .failure(let error):
            resources.continuation.resume(throwing: error)
        }
    }
}
