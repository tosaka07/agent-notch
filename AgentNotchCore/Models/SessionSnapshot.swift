import Foundation

/// Versioned file payload used by the GUI persistence adapter.
///
/// Keeping an envelope around the array lets future releases migrate the on-disk shape without
/// turning `UnifiedSession` itself into a persistence model.
public struct SessionSnapshotEnvelope: Codable, Sendable {
    public static let minimumSupportedSchemaVersion = 1
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let savedAt: Date
    public let sessions: [SessionSnapshot]

    public init(
        schemaVersion: Int = SessionSnapshotEnvelope.currentSchemaVersion,
        savedAt: Date = Date(),
        sessions: [SessionSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.sessions = sessions
    }
}

/// The durable, card-visible part of a session.
///
/// Runtime-only state such as sockets, pending approvals, active tools, icons, and response
/// closures is intentionally excluded. Those values cannot be safely resumed after an app
/// restart.
public struct SessionSnapshot: Codable, Sendable {
    public let id: String
    public let agentType: AgentType
    public let model: String?
    public let cwd: String?
    public let lastKnownStatus: SessionStatus
    public let startedAt: Date
    public let endedAt: Date?
    public let lastActivityAt: Date
    public let lastResumedAt: Date?

    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCachedTokens: Int
    public let estimatedCost: Double
    public let toolCallCount: Int

    public let pid: Int32?
    public let tty: String?
    public let transcriptPath: String?
    public let terminalAppName: String?
    public let tmuxPaneTarget: String?
    public let herdrPaneTarget: String?

    public let sessionTitle: String?
    public let firstUserPrompt: String?
    public let lastUserPrompt: String?
    public let lastAssistantMessage: String?
    public let permissionMode: PermissionMode?
    public let teamName: String?
    public let teammateName: String?
    public let tasks: [AgentTask]

    public init(session: UnifiedSession) {
        id = session.id
        agentType = session.agentType
        model = session.model
        cwd = session.cwd
        lastKnownStatus = session.lastKnownStatus ?? session.status
        startedAt = session.startedAt
        endedAt = session.endedAt
        lastActivityAt = session.lastActivityAt
        lastResumedAt = session.lastResumedAt

        totalInputTokens = session.totalInputTokens
        totalOutputTokens = session.totalOutputTokens
        totalCachedTokens = session.totalCachedTokens
        estimatedCost = session.estimatedCost
        toolCallCount = session.toolCallCount

        pid = session.pid
        tty = session.tty
        transcriptPath = session.transcriptPath
        terminalAppName = session.terminalAppName
        tmuxPaneTarget = session.tmuxPaneTarget
        herdrPaneTarget = session.herdrPaneTarget

        sessionTitle = session.sessionTitle
        firstUserPrompt = session.firstUserPrompt
        lastUserPrompt = session.lastUserPrompt
        lastAssistantMessage = session.lastAssistantMessage
        permissionMode = session.permissionMode
        teamName = session.teamName
        teammateName = session.teammateName
        tasks = session.tasks
    }

    /// Rebuilds a safe, non-actionable session. A fresh hook event promotes it to `.live`.
    public func makeRestoredSession() -> UnifiedSession {
        let session = UnifiedSession(
            id: id,
            agentType: agentType,
            model: model,
            cwd: cwd,
            // A persisted active state is historical, not proof that work is still running.
            status: .idle,
            startedAt: startedAt
        )
        session.presence = .restored
        session.lastKnownStatus = lastKnownStatus
        session.endedAt = endedAt
        session.lastActivityAt = lastActivityAt
        session.lastResumedAt = lastResumedAt

        session.totalInputTokens = totalInputTokens
        session.totalOutputTokens = totalOutputTokens
        session.totalCachedTokens = totalCachedTokens
        session.estimatedCost = estimatedCost
        session.toolCallCount = toolCallCount

        session.pid = pid
        session.tty = tty
        session.transcriptPath = transcriptPath
        session.terminalAppName = terminalAppName
        session.tmuxPaneTarget = tmuxPaneTarget
        session.herdrPaneTarget = herdrPaneTarget
        session.terminalInfoResolved = false

        session.sessionTitle = sessionTitle
        session.sessionTitleResolved = sessionTitle != nil
        session.firstUserPrompt = firstUserPrompt
        session.firstUserPromptResolved = firstUserPrompt != nil
        session.lastUserPrompt = lastUserPrompt
        session.lastAssistantMessage = lastAssistantMessage
        session.permissionMode = permissionMode
        session.teamName = teamName
        session.teammateName = teammateName
        session.tasks = tasks
        return session
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case agentType
        case model
        case cwd
        case lastKnownStatus
        case startedAt
        case endedAt
        case lastActivityAt
        case lastResumedAt
        case totalInputTokens
        case totalOutputTokens
        case totalCachedTokens
        case estimatedCost
        case toolCallCount
        case pid
        case tty
        case transcriptPath
        case terminalAppName
        case tmuxPaneTarget
        case herdrPaneTarget
        case sessionTitle
        case firstUserPrompt
        case lastUserPrompt
        case lastAssistantMessage
        case permissionMode
        case teamName
        case teammateName
        case tasks
    }

    /// Schema v1 did not persist tasks. Treating a missing key as an empty list
    /// provides the v1 → v2 migration without weakening any other required
    /// persisted fields.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        agentType = try container.decode(AgentType.self, forKey: .agentType)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        lastKnownStatus = try container.decode(SessionStatus.self, forKey: .lastKnownStatus)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        lastActivityAt = try container.decode(Date.self, forKey: .lastActivityAt)
        lastResumedAt = try container.decodeIfPresent(Date.self, forKey: .lastResumedAt)

        totalInputTokens = try container.decode(Int.self, forKey: .totalInputTokens)
        totalOutputTokens = try container.decode(Int.self, forKey: .totalOutputTokens)
        totalCachedTokens = try container.decode(Int.self, forKey: .totalCachedTokens)
        estimatedCost = try container.decode(Double.self, forKey: .estimatedCost)
        toolCallCount = try container.decode(Int.self, forKey: .toolCallCount)

        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        terminalAppName = try container.decodeIfPresent(String.self, forKey: .terminalAppName)
        tmuxPaneTarget = try container.decodeIfPresent(String.self, forKey: .tmuxPaneTarget)
        herdrPaneTarget = try container.decodeIfPresent(String.self, forKey: .herdrPaneTarget)

        sessionTitle = try container.decodeIfPresent(String.self, forKey: .sessionTitle)
        firstUserPrompt = try container.decodeIfPresent(String.self, forKey: .firstUserPrompt)
        lastUserPrompt = try container.decodeIfPresent(String.self, forKey: .lastUserPrompt)
        lastAssistantMessage = try container.decodeIfPresent(
            String.self, forKey: .lastAssistantMessage)
        permissionMode = try container.decodeIfPresent(PermissionMode.self, forKey: .permissionMode)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName)
        teammateName = try container.decodeIfPresent(String.self, forKey: .teammateName)
        tasks = try container.decodeIfPresent([AgentTask].self, forKey: .tasks) ?? []
    }
}
