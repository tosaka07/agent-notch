import Foundation
import Testing

@testable import AgentNotchCore

@Suite("Claude usage client", .serialized)
struct ClaudeUsageClientTests {
    private final class CredentialsState: @unchecked Sendable {
        private let lock = NSLock()
        private var storedCredentials: ClaudeCredentials?
        private var storedCalls = 0

        init(_ credentials: ClaudeCredentials?) {
            storedCredentials = credentials
        }

        var credentials: ClaudeCredentials? {
            get { lock.withLock { storedCredentials } }
            set { lock.withLock { storedCredentials = newValue } }
        }

        var calls: Int {
            lock.withLock { storedCalls }
        }

        func load() -> ClaudeCredentials? {
            lock.withLock {
                storedCalls += 1
                return storedCredentials
            }
        }
    }

    private final class RequestState: @unchecked Sendable {
        private let lock = NSLock()
        private var storedRequests: [URLRequest] = []

        var requests: [URLRequest] {
            lock.withLock { storedRequests }
        }

        func append(_ request: URLRequest) {
            lock.withLock { storedRequests.append(request) }
        }
    }

    private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

        nonisolated(unsafe) static var handler: Handler?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(
                    self,
                    didFailWithError: URLError(.resourceUnavailable)
                )
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(
                    self,
                    didReceive: response,
                    cacheStoragePolicy: .notAllowed
                )
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    @Test("No OAuth token skips the network request")
    func noTokenSkipsNetwork() async {
        let credentials = ClaudeCredentialsProvider(loader: { nil })
        let requests = RequestState()
        let session = makeSession { request in
            requests.append(request)
            throw URLError(.badServerResponse)
        }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(session: session, credentials: credentials)

        #expect(await client.fetchUsage() == nil)
        #expect(requests.requests.isEmpty)
    }

    @Test("A successful response sends OAuth headers and parses usage")
    func successfulResponse() async throws {
        let credentials = ClaudeCredentialsProvider(
            loader: { ClaudeCredentials(accessToken: "test-token") }
        )
        let requests = RequestState()
        let session = makeSession { request in
            requests.append(request)
            return (
                Self.response(for: request, statusCode: 200),
                Data(#"{"five_hour":{"utilization":25}}"#.utf8)
            )
        }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(session: session, credentials: credentials)

        let snapshot = try #require(await client.fetchUsage())

        #expect(snapshot.session?.usedPercent == 25)
        let request = try #require(requests.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "claude-code/2.0.0")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Unauthorized responses invalidate cached credentials before the next fetch")
    func unauthorizedInvalidatesCredentials() async throws {
        let credentialState = CredentialsState(
            ClaudeCredentials(accessToken: "expired-token")
        )
        let credentials = ClaudeCredentialsProvider(loader: { credentialState.load() })
        let requests = RequestState()
        let session = makeSession { request in
            requests.append(request)
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            if authorization == "Bearer expired-token" {
                return (Self.response(for: request, statusCode: 401), Data())
            }
            return (
                Self.response(for: request, statusCode: 200),
                Data(#"{"seven_day":{"utilization":50}}"#.utf8)
            )
        }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(session: session, credentials: credentials)

        #expect(await client.fetchUsage() == nil)
        credentialState.credentials = ClaudeCredentials(accessToken: "rotated-token")
        let recovered = try #require(await client.fetchUsage())

        #expect(recovered.weekAllModels?.usedPercent == 50)
        #expect(credentialState.calls == 2)
        #expect(
            requests.requests.last?.value(forHTTPHeaderField: "Authorization")
                == "Bearer rotated-token"
        )
    }

    @Test("Network failures return nil")
    func networkFailure() async {
        let credentials = ClaudeCredentialsProvider(
            loader: { ClaudeCredentials(accessToken: "test-token") }
        )
        let session = makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(session: session, credentials: credentials)

        #expect(await client.fetchUsage() == nil)
    }

    // MARK: - Unavailable reasons
    //
    // The gauge stays on screen whatever happens, so every failure has to name itself; a bare
    // nil would leave the surface with nothing to say. These pin each cause to its reason.

    @Test("Missing credentials report notSignedIn without touching the network")
    func missingCredentialsReportNotSignedIn() async {
        let requests = RequestState()
        let session = makeSession { request in
            requests.append(request)
            throw URLError(.badServerResponse)
        }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(
            session: session,
            credentials: ClaudeCredentialsProvider(loader: { nil })
        )

        #expect(await client.fetch() == .unavailable(.notSignedIn))
        #expect(requests.requests.isEmpty)
    }

    /// The regression this whole change exists for: Claude Code owns token refresh, so an
    /// expired token is a wait-for-Claude-Code state, not a failure — and it must not spend a
    /// request that is certain to 401.
    @Test("An expired token reports tokenExpired and skips the request")
    func expiredTokenReportsTokenExpired() async {
        let requests = RequestState()
        let session = makeSession { request in
            requests.append(request)
            throw URLError(.badServerResponse)
        }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(
            session: session,
            credentials: ClaudeCredentialsProvider(
                loader: {
                    ClaudeCredentials(
                        accessToken: "stale-token",
                        expiresAt: Date().addingTimeInterval(-3600)
                    )
                }
            )
        )

        #expect(await client.fetch() == .unavailable(.tokenExpired))
        #expect(requests.requests.isEmpty)
    }

    @Test(
        "HTTP statuses map to distinct reasons",
        arguments: [
            (401, UsageUnavailableReason.unauthorized),
            (403, UsageUnavailableReason.unauthorized),
            (429, UsageUnavailableReason.rateLimited),
            (500, UsageUnavailableReason.networkError),
        ])
    func httpStatusesMapToReasons(status: Int, expected: UsageUnavailableReason) async {
        let session = makeSession { request in
            (Self.response(for: request, statusCode: status), Data())
        }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(
            session: session,
            credentials: ClaudeCredentialsProvider(
                loader: { ClaudeCredentials(accessToken: "test-token") }
            )
        )

        #expect(await client.fetch() == .unavailable(expected))
    }

    /// A 200 carrying no window is an account without rate limits, not a fault — saying
    /// "couldn't fetch" there would send the user chasing a problem that does not exist.
    @Test("A 200 with no usable window reports noLimits")
    func emptyPayloadReportsNoLimits() async {
        let session = makeSession { request in
            (Self.response(for: request, statusCode: 200), Data("{}".utf8))
        }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(
            session: session,
            credentials: ClaudeCredentialsProvider(
                loader: { ClaudeCredentials(accessToken: "test-token") }
            )
        )

        #expect(await client.fetch() == .unavailable(.noLimits))
    }

    @Test("Network failures report networkError")
    func networkFailureReportsNetworkError() async {
        let session = makeSession { _ in throw URLError(.notConnectedToInternet) }
        defer { session.invalidateAndCancel() }
        let client = ClaudeUsageClient(
            session: session,
            credentials: ClaudeCredentialsProvider(
                loader: { ClaudeCredentials(accessToken: "test-token") }
            )
        )

        #expect(await client.fetch() == .unavailable(.networkError))
    }

    private func makeSession(
        handler: @escaping StubURLProtocol.Handler
    ) -> URLSession {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
