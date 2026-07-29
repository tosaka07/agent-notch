import AgentNotchCore
import Combine
import Defaults
import Foundation

protocol CodexSharedQuestionTransport: AnyObject, Sendable {
    func start()
    func stop()
    func setFollowedThreadIds(_ ids: Set<String>)
    func submit(requestId: CodexRPCID, answers: [String: [String]]) async throws
}

protocol CodexDesktopQuestionTransport: AnyObject, Sendable {
    func start()
    func stop()
    func setFollowedThreadIds(_ ids: Set<String>)
    func submit(
        threadId: String,
        requestId: CodexRPCID,
        answers: [String: [String]]
    ) async throws
}

extension CodexSharedAppServerClient: CodexSharedQuestionTransport {}
extension CodexDesktopIPCClient: CodexDesktopQuestionTransport {}

/// Owns the complete Codex question lifecycle.
///
/// Hook and rollout inputs are observation adapters: they make a question
/// visible and recover it after restart, but cannot answer it. App Server and
/// Codex Desktop IPC are response adapters. Correlating both sides here keeps
/// the UI independent of transport details and ensures a duplicate observation
/// neither re-opens the panel nor plays a second attention sound.
@MainActor
final class CodexQuestionCoordinator {
    private enum Source: String, Hashable {
        case sharedAppServer
        case desktopIPC
    }

    private struct RequestKey: Hashable {
        let source: Source
        let threadId: String
        let requestId: CodexRPCID
    }

    /// `requestId` is stable between the shared App Server and Desktop IPC;
    /// the source is intentionally excluded so either transport can settle a
    /// replay from the other one.
    private struct RequestIdentity: Hashable {
        let threadId: String
        let requestId: CodexRPCID

        init(_ key: RequestKey) {
            threadId = key.threadId
            requestId = key.requestId
        }
    }

    private struct ObservationKey: Hashable {
        let sessionId: String
        let callId: String
    }

    private struct RecordKey: Hashable {
        let sessionId: String
        let toolUseId: String
    }

    private struct Record {
        let key: RecordKey
        var turnId: String?
        var questions: [AskQuestionInfo.Question]
        var expiresAt: Date
        var directRoutes: Set<RequestKey>
        var observationKeys: Set<ObservationKey>
        var directDeliveryUnavailable: Bool
        let receivedAt: Date

        var responseMode: QuestionResponseMode {
            directRoutes.isEmpty || directDeliveryUnavailable ? .terminalOnly : .direct
        }
    }

    private let sessionManager: SessionManager
    private var sharedTransport: (any CodexSharedQuestionTransport)?
    private var desktopTransport: (any CodexDesktopQuestionTransport)?
    private var rolloutMonitor: (any CodexRolloutQuestionMonitoring)?
    private let usesInjectedTransports: Bool
    private let usesInjectedMonitor: Bool
    private var sessionChangeSubscription: AnyCancellable?

    private var records: [RecordKey: Record] = [:]
    private var recordKeyByRequest: [RequestKey: RecordKey] = [:]
    private var recordKeyByObservation: [ObservationKey: RecordKey] = [:]
    private var rolloutCallIdsBySession: [String: Set<String>] = [:]
    private var dismissedRequestIdentities = Set<RequestIdentity>()
    private var dismissedObservations = Set<ObservationKey>()
    /// A response stream can replay its last request after reconnecting, while
    /// an observation stream can lag behind a direct resolution. Keep settled
    /// identities for this coordinator lifetime so a terminal transition never
    /// turns back into a banner because a delayed adapter caught up late.
    private var settledRequestIdentities = Set<RequestIdentity>()
    private var settledObservations = Set<ObservationKey>()

    private var started = false
    private var sharedTransportStarted = false
    private var desktopTransportStarted = false
    private var rolloutMonitorStarted = false
    private var integrationObservation: Defaults.Observation?

    init(
        sessionManager: SessionManager,
        sharedTransport: (any CodexSharedQuestionTransport)? = nil,
        desktopTransport: (any CodexDesktopQuestionTransport)? = nil,
        rolloutMonitor: (any CodexRolloutQuestionMonitoring)? = nil
    ) {
        self.sessionManager = sessionManager
        self.sharedTransport = sharedTransport
        self.desktopTransport = desktopTransport
        self.rolloutMonitor = rolloutMonitor
        usesInjectedTransports = sharedTransport != nil || desktopTransport != nil
        usesInjectedMonitor = rolloutMonitor != nil
    }

    func start() {
        guard !started else { return }
        started = true
        sessionChangeSubscription = sessionManager.objectWillChange.sink { [weak self] _ in
            // SessionManager publishes before assigning. Wait one executor turn
            // so new/restored transcript paths are visible to the monitor.
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.refreshTrackedSessions()
            }
        }

        applyIntegrationSetting()
        observeIntegrationSetting()
    }

    func stop() {
        guard started else { return }
        started = false
        sessionChangeSubscription = nil
        integrationObservation = nil
        sharedTransport?.stop()
        desktopTransport?.stop()
        rolloutMonitor?.stop()
        sharedTransportStarted = false
        desktopTransportStarted = false
        rolloutMonitorStarted = false
    }

    func canHandle(sessionId: String, toolUseId: String) -> Bool {
        guard let record = records[RecordKey(sessionId: sessionId, toolUseId: toolUseId)]
        else { return false }
        return record.responseMode == .direct
    }

    func answer(
        sessionId: String,
        toolUseId: String,
        answers: [String: [String]]
    ) {
        let recordKey = RecordKey(sessionId: sessionId, toolUseId: toolUseId)
        guard let record = records[recordKey],
            record.responseMode == .direct,
            let route = preferredRoute(in: record),
            let session = sessionManager.session(for: sessionId),
            var pending = session.pendingInterruptions.question(toolUseId: toolUseId),
            !pending.isSubmitting
        else { return }

        pending.phase = .submitting
        session.pendingInterruptions.enqueue(pending)
        sessionManager.notifyChange()

        Task { [weak self] in
            guard let self else { return }
            do {
                switch route.source {
                case .sharedAppServer:
                    guard let sharedTransport else {
                        throw CodexSharedAppServerClientError.unavailable
                    }
                    try await sharedTransport.submit(
                        requestId: route.requestId,
                        answers: answers
                    )
                case .desktopIPC:
                    guard let desktopTransport else {
                        throw CodexDesktopIPCError.unavailable
                    }
                    try await desktopTransport.submit(
                        threadId: route.threadId,
                        requestId: route.requestId,
                        answers: answers
                    )
                }
                await waitForResolution(recordKey: recordKey)
            } catch {
                downgradeToTerminal(recordKey: recordKey, error: error)
            }
        }
    }

    func dismiss(sessionId: String, toolUseId: String) {
        let key = RecordKey(sessionId: sessionId, toolUseId: toolUseId)
        removeRecord(key, rememberDismissal: true)
    }

    // MARK: - Observation adapters

    func receiveHookQuestion(_ info: AskQuestionInfo, turnId: String?) {
        observe(
            sessionId: info.sessionId,
            callId: info.toolUseId,
            turnId: turnId,
            questions: info.questions,
            expiresAt: .distantFuture,
            receivedAt: Date()
        )
    }

    func receiveObservedResolution(sessionId: String, toolUseId: String) {
        let observation = ObservationKey(sessionId: sessionId, callId: toolUseId)
        settledObservations.insert(observation)
        if let recordKey = recordKeyByObservation[observation] {
            resolveRecord(recordKey)
            return
        }

        // Some Codex versions use different item and call identifiers across
        // hook and App Server envelopes. Fall back only when one live question
        // makes the answer unambiguous; concurrent subagents can otherwise
        // place multiple requests in the same session queue.
        guard let session = sessionManager.session(for: sessionId) else { return }
        let candidates = records.keys.filter {
            $0.sessionId == sessionId
                && session.pendingInterruptions.question(toolUseId: $0.toolUseId) != nil
        }
        if candidates.count == 1, let recordKey = candidates.first {
            resolveRecord(recordKey)
        }
    }

    func receiveRolloutSnapshot(
        sessionId: String,
        questions: [CodexRolloutQuestion]
    ) {
        let liveCallIds = Set(questions.map(\.callId))
        let previousCallIds = rolloutCallIdsBySession[sessionId] ?? []
        rolloutCallIdsBySession[sessionId] = liveCallIds

        for callId in previousCallIds.subtracting(liveCallIds) {
            let key = ObservationKey(sessionId: sessionId, callId: callId)
            if let recordKey = recordKeyByObservation[key] {
                resolveRecord(recordKey)
            }
        }

        for question in questions {
            observe(
                sessionId: sessionId,
                callId: question.callId,
                turnId: question.turnId,
                questions: question.questions,
                expiresAt: question.expiresAt,
                receivedAt: question.receivedAt
            )
        }
    }

    // MARK: - Direct response adapters

    func receiveSharedRequest(_ request: CodexUserInputRequest) {
        upsert(request, source: .sharedAppServer)
    }

    func receiveSharedResolution(_ resolved: CodexResolvedUserInput) {
        resolve(
            RequestKey(
                source: .sharedAppServer,
                threadId: resolved.threadId,
                requestId: resolved.requestId
            )
        )
    }

    func receiveDesktopSnapshot(
        threadId: String,
        requests: [CodexUserInputRequest]
    ) {
        let liveKeys = Set(
            requests.map {
                RequestKey(
                    source: .desktopIPC,
                    threadId: threadId,
                    requestId: $0.requestId
                )
            })
        for key in Array(recordKeyByRequest.keys)
        where key.source == .desktopIPC && key.threadId == threadId && !liveKeys.contains(key) {
            resolve(key)
        }
        for request in requests {
            upsert(request, source: .desktopIPC)
        }
    }

    // MARK: - Correlation

    private func observe(
        sessionId: String,
        callId: String,
        turnId: String?,
        questions: [AskQuestionInfo.Question],
        expiresAt: Date,
        receivedAt: Date
    ) {
        let observationKey = ObservationKey(sessionId: sessionId, callId: callId)
        guard !dismissedObservations.contains(observationKey),
            !settledObservations.contains(observationKey)
        else { return }
        if let existingKey = recordKeyByObservation[observationKey] {
            present(existingKey)
            return
        }

        let recordKey =
            matchingRecord(
                sessionId: sessionId,
                preferredToolUseId: callId,
                turnId: turnId,
                questions: questions,
                allowContentOnlyFallback: false
            )
            ?? uniqueRecordKey(sessionId: sessionId, preferredToolUseId: callId)

        if var record = records[recordKey] {
            record.observationKeys.insert(observationKey)
            record.turnId = record.turnId ?? turnId
            records[recordKey] = record
        } else {
            records[recordKey] = Record(
                key: recordKey,
                turnId: turnId,
                questions: questions,
                expiresAt: expiresAt,
                directRoutes: [],
                observationKeys: [observationKey],
                directDeliveryUnavailable: false,
                receivedAt: receivedAt
            )
        }
        recordKeyByObservation[observationKey] = recordKey
        present(recordKey)
    }

    private func upsert(_ request: CodexUserInputRequest, source: Source) {
        let requestKey = RequestKey(
            source: source,
            threadId: request.threadId,
            requestId: request.requestId
        )
        guard !dismissedRequestIdentities.contains(RequestIdentity(requestKey)),
            !settledRequestIdentities.contains(RequestIdentity(requestKey))
        else { return }
        if let existingKey = recordKeyByRequest[requestKey] {
            if var record = records[existingKey], record.directDeliveryUnavailable {
                // A replay after reconnect proves a live response path exists
                // again. Re-enable direct answering without creating a banner.
                record.directDeliveryUnavailable = false
                records[existingKey] = record
            }
            present(existingKey)
            return
        }

        let questions = request.questions.map(\.bannerQuestion)
        let recordKey =
            matchingRecord(
                sessionId: request.threadId,
                preferredToolUseId: request.itemId,
                turnId: request.turnId,
                questions: questions,
                allowContentOnlyFallback: true
            )
            ?? uniqueRecordKey(
                sessionId: request.threadId,
                preferredToolUseId: request.itemId.isEmpty
                    ? "codex-input-\(request.requestId.displayKey)"
                    : request.itemId
            )

        if var record = records[recordKey] {
            record.directRoutes.insert(requestKey)
            record.directDeliveryUnavailable = false
            record.expiresAt = request.expiresAt
            record.turnId = record.turnId ?? request.turnId
            // The direct protocol carries richer fields such as isSecret and
            // isOther; prefer it over an observe-only hook projection.
            record.questions = questions
            records[recordKey] = record
        } else {
            records[recordKey] = Record(
                key: recordKey,
                turnId: request.turnId,
                questions: questions,
                expiresAt: request.expiresAt,
                directRoutes: [requestKey],
                observationKeys: [],
                directDeliveryUnavailable: false,
                receivedAt: request.receivedAt
            )
        }
        recordKeyByRequest[requestKey] = recordKey
        present(recordKey)
    }

    private func matchingRecord(
        sessionId: String,
        preferredToolUseId: String,
        turnId: String?,
        questions: [AskQuestionInfo.Question],
        allowContentOnlyFallback: Bool
    ) -> RecordKey? {
        let preferredKey = RecordKey(
            sessionId: sessionId,
            toolUseId: preferredToolUseId
        )
        if records[preferredKey] != nil {
            return preferredKey
        }

        let candidates = records.compactMap { key, record -> RecordKey? in
            guard key.sessionId == sessionId else { return nil }
            if let turnId, let recordTurnId = record.turnId,
                turnId == recordTurnId, questionsMatch(record.questions, questions)
            {
                return key
            }
            guard allowContentOnlyFallback,
                record.directRoutes.isEmpty,
                sessionManager.session(for: sessionId)?
                    .pendingInterruptions.question(toolUseId: key.toolUseId) != nil,
                questionsMatch(record.questions, questions)
            else { return nil }
            return key
        }
        // Content-only correlation is safe only when it has one possible
        // target. Dictionary iteration used to choose arbitrarily here, which
        // made concurrent identical questions nondeterministic.
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// Observation payloads do not always carry App Server-only presentation
    /// flags. Correlation therefore uses the stable question identity and
    /// visible choices, then lets the direct payload replace the projection.
    private func questionsMatch(
        _ lhs: [AskQuestionInfo.Question],
        _ rhs: [AskQuestionInfo.Question]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.responseKey == right.responseKey
                && left.question == right.question
                && left.header == right.header
                && left.options == right.options
        }
    }

    private func uniqueRecordKey(
        sessionId: String,
        preferredToolUseId: String
    ) -> RecordKey {
        let preferred = RecordKey(sessionId: sessionId, toolUseId: preferredToolUseId)
        guard records[preferred] != nil else { return preferred }
        return RecordKey(
            sessionId: sessionId,
            toolUseId: "\(preferredToolUseId)-\(UUID().uuidString)"
        )
    }

    // MARK: - Session and presentation lifecycle

    private func refreshTrackedSessions() {
        guard started else { return }
        let codexSessions = sessionManager.sessions.values.filter {
            $0.agentType == .codex && $0.status != .completed
        }
        let codexThreadIds = Set(codexSessions.map(\.id))
        let watchedTranscripts = Dictionary(
            uniqueKeysWithValues: codexSessions.compactMap { session in
                session.transcriptPath.map { (session.id, $0) }
            }
        )
        rolloutMonitor?.setWatchedSessions(watchedTranscripts)

        if codexThreadIds.isEmpty {
            sharedTransport?.setFollowedThreadIds([])
            desktopTransport?.setFollowedThreadIds([])
            if desktopTransportStarted {
                desktopTransport?.stop()
                desktopTransportStarted = false
            }
            return
        }

        ensureTransports()
        if !sharedTransportStarted {
            sharedTransport?.start()
            sharedTransportStarted = sharedTransport != nil
        }
        sharedTransport?.setFollowedThreadIds(codexThreadIds)
        desktopTransport?.setFollowedThreadIds(codexThreadIds)
        if !desktopTransportStarted {
            desktopTransport?.start()
            desktopTransportStarted = desktopTransport != nil
        }

        let pendingRecords = records.values
            .filter { codexThreadIds.contains($0.key.sessionId) }
            .sorted { $0.receivedAt < $1.receivedAt }
        for record in pendingRecords {
            present(record.key)
        }
    }

    private func ensureTransports() {
        if !usesInjectedTransports, sharedTransport == nil,
            let executableURL = CodexExecutableResolver.resolve()
        {
            sharedTransport = CodexSharedAppServerClient(
                executableURL: executableURL,
                onRequest: { [weak self] request in
                    Task { @MainActor [weak self] in
                        self?.receiveSharedRequest(request)
                    }
                },
                onResolved: { [weak self] resolved in
                    Task { @MainActor [weak self] in
                        self?.receiveSharedResolution(resolved)
                    }
                }
            )
        }

        if !usesInjectedTransports, desktopTransport == nil {
            desktopTransport = CodexDesktopIPCClient { [weak self] threadId, requests in
                Task { @MainActor [weak self] in
                    self?.receiveDesktopSnapshot(threadId: threadId, requests: requests)
                }
            }
        }
    }

    /// Starts or stops **every** Codex adapter to match `Defaults[.codexIntegrationEnabled]`.
    ///
    /// All three touch Codex: the rollout monitor opens its log files, the shared transport spawns
    /// `codex app-server`, and the Desktop IPC client connects to the Codex app. Gating only the
    /// log reader left the other two running while the switch said off — which is the same lie in a
    /// quieter form. The hook is not gated here: it stops because the switch removes it from
    /// `hooks.json`.
    private func applyIntegrationSetting() {
        guard started else { return }
        if Defaults[.codexIntegrationEnabled] {
            ensureTransports()
            ensureRolloutMonitor()
            // Keep a shared daemon connection ready before a future CLI session
            // chooses its transport. Detection does not depend on this connection.
            if !sharedTransportStarted {
                sharedTransport?.start()
                sharedTransportStarted = sharedTransport != nil
            }
            if !rolloutMonitorStarted {
                rolloutMonitor?.start()
                rolloutMonitorStarted = rolloutMonitor != nil
            }
            refreshTrackedSessions()
        } else {
            sharedTransport?.stop()
            desktopTransport?.stop()
            rolloutMonitor?.stop()
            sharedTransportStarted = false
            desktopTransportStarted = false
            rolloutMonitorStarted = false
        }
    }

    private func observeIntegrationSetting() {
        integrationObservation = Defaults.observe(.codexIntegrationEnabled) { [weak self] _ in
            Task { @MainActor in
                self?.applyIntegrationSetting()
            }
        }
    }

    private func ensureRolloutMonitor() {
        guard !usesInjectedMonitor, rolloutMonitor == nil else { return }
        rolloutMonitor = CodexRolloutQuestionMonitor { [weak self] sessionId, questions in
            Task { @MainActor [weak self] in
                self?.receiveRolloutSnapshot(sessionId: sessionId, questions: questions)
            }
        }
    }

    private func present(_ key: RecordKey) {
        guard let record = records[key],
            let session = sessionManager.session(for: key.sessionId),
            session.agentType == .codex,
            session.status != .completed
        else { return }

        if let current = session.pendingInterruptions.question(toolUseId: key.toolUseId) {
            let mode = record.responseMode
            session.pendingInterruptions.enqueue(
                PendingQuestion(
                    toolUseId: key.toolUseId,
                    questions: record.questions,
                    receivedAt: current.receivedAt,
                    expiresAt: mode == .direct ? record.expiresAt : .distantFuture,
                    responseMode: mode,
                    isExpired: mode == .direct && current.isExpired,
                    isSubmitting: mode == .direct && current.isSubmitting
                )
            )
            sessionManager.notifyChange()
            return
        }

        let inserted = session.pendingInterruptions.enqueue(
            PendingQuestion(
                toolUseId: key.toolUseId,
                questions: record.questions,
                receivedAt: record.receivedAt,
                expiresAt: record.responseMode == .direct ? record.expiresAt : .distantFuture,
                responseMode: record.responseMode
            )
        )
        session.status = .permissionWaiting
        sessionManager.notifyChange()

        if inserted, !sessionManager.isMuted(session.id) {
            SoundPlayer.play(.question)
            NotificationCenter.default.post(name: .agentNotchAutoExpand, object: session.id)
        }
    }

    private func resolve(_ requestKey: RequestKey) {
        settledRequestIdentities.insert(RequestIdentity(requestKey))
        guard let recordKey = recordKeyByRequest[requestKey] else { return }
        resolveRecord(recordKey)
    }

    private func resolveRecord(_ key: RecordKey) {
        guard let record = records[key] else { return }
        settledRequestIdentities.formUnion(record.directRoutes.map(RequestIdentity.init))
        settledObservations.formUnion(record.observationKeys)

        let sessionId = key.sessionId
        guard let session = sessionManager.session(for: sessionId) else {
            removeRecord(key, rememberDismissal: false)
            return
        }
        if session.pendingInterruptions.remove(
            kind: .question, toolUseId: key.toolUseId
        ) {
            session.status = session.statusAfterPermissionResolved()
        }
        removeRecord(key, rememberDismissal: false)
        sessionManager.notifyChange()
    }

    private func removeRecord(_ key: RecordKey, rememberDismissal: Bool) {
        guard let record = records.removeValue(forKey: key) else { return }
        for request in record.directRoutes {
            recordKeyByRequest.removeValue(forKey: request)
            if rememberDismissal {
                dismissedRequestIdentities.insert(RequestIdentity(request))
            }
        }
        for observation in record.observationKeys {
            recordKeyByObservation.removeValue(forKey: observation)
            if rememberDismissal {
                dismissedObservations.insert(observation)
            }
        }
    }

    private func preferredRoute(in record: Record) -> RequestKey? {
        let sessionOwnsTerminal =
            sessionManager.session(for: record.key.sessionId)?.isTerminalJumpAvailable == true
        let preferredSource: Source = sessionOwnsTerminal ? .sharedAppServer : .desktopIPC
        return record.directRoutes.first { $0.source == preferredSource }
            ?? record.directRoutes.first
    }

    private func waitForResolution(recordKey: RecordKey) async {
        try? await Task.sleep(for: .seconds(10))
        guard records[recordKey] != nil,
            sessionManager.session(for: recordKey.sessionId)?
                .pendingInterruptions.question(toolUseId: recordKey.toolUseId)?
                .isSubmitting == true
        else { return }
        downgradeToTerminal(
            recordKey: recordKey,
            error: CodexSharedAppServerClientError.unavailable
        )
        Log.socket.warning(
            "Codex user-input response was not confirmed session=\(recordKey.sessionId)"
        )
    }

    private func downgradeToTerminal(recordKey: RecordKey, error: any Error) {
        guard var record = records[recordKey] else { return }
        record.directDeliveryUnavailable = true
        records[recordKey] = record
        present(recordKey)
        Log.socket.warning(
            "Codex user-input direct response unavailable session=\(recordKey.sessionId): \(error.localizedDescription)"
        )
    }
}
