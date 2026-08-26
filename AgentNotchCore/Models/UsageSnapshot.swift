import Foundation

/// Usage severity, mirroring the API's `severity` (`normal` / `warning` / `critical`).
/// Kept so the API's judgement can take precedence over our own 70%/90% thresholds.
public enum UsageSeverity: String, Sendable, Equatable {
    case normal
    case warning
    case critical

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "warning": self = .warning
        case "critical", "error": self = .critical
        default: self = .normal
        }
    }
}

/// A single usage window (e.g. the 5-hour session window, the weekly window).
/// An agent-agnostic representation shared by Claude and Codex.
public struct UsageWindow: Sendable, Equatable {
    /// Usage percentage from 0 to 100.
    public let usedPercent: Double
    /// Scheduled reset time; nil when unavailable.
    public let resetsAt: Date?
    /// Severity as returned by the API; nil when unavailable, in which case the UI decides from the percentage.
    public let severity: UsageSeverity?
    /// Whether this window is the one currently binding (`limits[].is_active`), i.e. which of the
    /// several windows is the present bottleneck.
    public let isActive: Bool

    public init(
        usedPercent: Double,
        resetsAt: Date?,
        severity: UsageSeverity? = nil,
        isActive: Bool = false
    ) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.severity = severity
        self.isActive = isActive
    }
}

/// Per-model weekly window.
///
/// The model name comes from `limits[].scope.model.display_name` (e.g. "Fable", "Opus").
/// The `seven_day_<model>` keys are all null in current responses; per-model data appears
/// only in the `limits` array.
public struct ModelUsageWindow: Sendable, Equatable, Identifiable {
    public let modelLabel: String
    public let window: UsageWindow

    public var id: String { modelLabel }

    public init(modelLabel: String, window: UsageWindow) {
        self.modelLabel = modelLabel
        self.window = window
    }
}

/// State of extra credits (pay-as-you-go on top of the plan), taken from `extra_usage` / `spend`.
public struct ExtraUsageInfo: Sendable, Equatable {
    /// Whether credit usage is enabled.
    public let isEnabled: Bool
    /// Amount spent, in currency units (`spend.used.amount_minor` divided by `exponent`).
    public let usedAmount: Double?
    /// Spend limit; nil when unlimited or unset.
    public let limitAmount: Double?
    /// Remaining balance.
    public let balanceAmount: Double?
    public let currency: String?
    /// Usage percentage.
    public let usedPercent: Double?
    /// Why credits are disabled (`out_of_credits`, ...).
    public let disabledReason: String?
    /// Whether the spend limit has been reached.
    public let spendLimitReached: Bool

    public init(
        isEnabled: Bool,
        usedAmount: Double?,
        limitAmount: Double?,
        balanceAmount: Double?,
        currency: String?,
        usedPercent: Double?,
        disabledReason: String?,
        spendLimitReached: Bool
    ) {
        self.isEnabled = isEnabled
        self.usedAmount = usedAmount
        self.limitAmount = limitAmount
        self.balanceAmount = balanceAmount
        self.currency = currency
        self.usedPercent = usedPercent
        self.disabledReason = disabledReason
        self.spendLimitReached = spendLimitReached
    }

    /// Whether there is anything worth showing (credits enabled, or a balance/spend exists).
    public var hasContent: Bool {
        isEnabled || (usedAmount ?? 0) > 0 || (balanceAmount ?? 0) > 0 || limitAmount != nil
    }
}

/// Snapshot equivalent to Claude Code's `/usage`, built from the response of the
/// undocumented `api.anthropic.com/api/oauth/usage` endpoint.
public struct ClaudeUsageSnapshot: Sendable, Equatable {
    /// Current session (5-hour window).
    public let session: UsageWindow?
    /// Current week, all models (7-day window).
    public let weekAllModels: UsageWindow?
    /// Per-model windows for the current week; several may be returned.
    public let weekModels: [ModelUsageWindow]
    /// Extra-credit (pay-as-you-go) state. Mostly nil on subscription-only setups.
    public let extraUsage: ExtraUsageInfo?

    public init(
        session: UsageWindow?,
        weekAllModels: UsageWindow?,
        weekModels: [ModelUsageWindow] = [],
        extraUsage: ExtraUsageInfo? = nil
    ) {
        self.session = session
        self.weekAllModels = weekAllModels
        self.weekModels = weekModels
        self.extraUsage = extraUsage
    }
}

/// A Codex usage-based allowance returned by Codex App Server.
///
/// App Server reports `remainingPercent` as a rounded integer, while `used` and
/// `limit` are decimal strings. The gauge is explicitly a consumed-percentage
/// gauge, so it derives its value from the precise amounts when possible rather
/// than accidentally displaying the remaining percentage as usage.
public struct CodexSpendLimit: Sendable, Equatable {
    public let used: Decimal
    public let limit: Decimal
    public let remainingPercent: Double
    public let resetsAt: Date

    public init(
        used: Decimal,
        limit: Decimal,
        remainingPercent: Double,
        resetsAt: Date
    ) {
        self.used = used
        self.limit = limit
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    /// Percentage consumed, kept separate from App Server's remaining percentage.
    public var usedPercent: Double {
        let usedValue = NSDecimalNumber(decimal: used).doubleValue
        let limitValue = NSDecimalNumber(decimal: limit).doubleValue
        if usedValue.isFinite, limitValue.isFinite, limitValue > 0 {
            return min(max(usedValue / limitValue * 100, 0), 100)
        }
        return 100 - remainingPercent
    }

    /// Adapts the allowance to the existing gauge/window presentation model.
    public var usageWindow: UsageWindow {
        UsageWindow(usedPercent: usedPercent, resetsAt: resetsAt)
    }
}

/// Codex CLI usage snapshot. App Server is the primary source; the rollout JSONL
/// parser supplies the same rolling-window fields as a compatibility fallback.
public struct CodexUsageSnapshot: Sendable, Equatable {
    /// Primary window (roughly 5 hours).
    public let primary: UsageWindow?
    /// Secondary window (roughly weekly).
    public let secondary: UsageWindow?
    /// Usage-based allowance. This is independent of the rolling windows.
    public let individualLimit: CodexSpendLimit?
    /// "plus", "pro", "business", etc.
    public let planType: String?

    public init(
        primary: UsageWindow?,
        secondary: UsageWindow?,
        planType: String?,
        individualLimit: CodexSpendLimit? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.individualLimit = individualLimit
    }
}

/// Which window the always-visible gauge shows (chosen in settings).
///
/// Each agent names its windows differently (Claude: session / week, Codex: primary / secondary),
/// so the choice is expressed at the semantic level of "roughly 5 hours" and "roughly a week".
/// If the chosen window does not exist for that agent it falls back to `auto`, because a setting
/// silently making the gauge disappear would be an unreasonable side effect.
public enum UsageGaugeMetric: String, Sendable, CaseIterable {
    /// Automatically pick the window under the most pressure (default).
    case auto
    /// Session window (Claude: current session, Codex: primary 5h).
    case session
    /// Weekly all-models window (Claude: current week all models, Codex: secondary).
    case weekly
    /// Highest of the per-model weekly windows (Claude only; Codex has none, so it falls back to auto).
    case weeklyModel
}

/// Why an agent's usage could not be obtained.
///
/// # Why a reason is carried rather than just `nil`
/// The gauge is a permanent surface: it stays visible even with nothing to show, so the user is
/// never left wondering whether the feature vanished. That only works if the surface can say
/// *why* it is empty — "the token expired, open Claude Code" and "this plan has no rate limits"
/// call for completely different reactions, and a bare `nil` conflates them.
public enum UsageUnavailableReason: String, Sendable, Equatable, CaseIterable {
    /// No credentials at all — the agent has never signed in on this Mac.
    case notSignedIn
    /// Credentials exist but the access token has expired. Agent Notch is read-only on
    /// credentials (see `ClaudeCredentialsStore`), so **only the agent itself can refresh them**;
    /// the token comes back the moment Claude Code runs again.
    case tokenExpired
    /// The endpoint rejected the token (401/403).
    case unauthorized
    /// Rate limited (429). Polling backs off on its own, so this resolves without user action.
    case rateLimited
    /// The request never completed.
    case networkError
    /// A response arrived but carried no window — e.g. pay-as-you-go with no rate limit.
    case noLimits
    /// The integration is switched off in settings.
    case integrationDisabled
    /// The agent's local tooling could not be reached (Codex's app server and rollout files).
    case agentUnreachable
}

/// Aggregated snapshot handed to the UI. Agents whose usage could not be fetched stay nil,
/// with the matching `UsageUnavailableReason` recorded alongside.
public struct UsageSnapshot: Sendable, Equatable {
    public let claude: ClaudeUsageSnapshot?
    public let codex: CodexUsageSnapshot?
    public let claudeUnavailable: UsageUnavailableReason?
    public let codexUnavailable: UsageUnavailableReason?
    public let fetchedAt: Date

    public init(
        claude: ClaudeUsageSnapshot?,
        codex: CodexUsageSnapshot?,
        claudeUnavailable: UsageUnavailableReason? = nil,
        codexUnavailable: UsageUnavailableReason? = nil,
        fetchedAt: Date
    ) {
        self.claude = claude
        self.codex = codex
        self.claudeUnavailable = claudeUnavailable
        self.codexUnavailable = codexUnavailable
        self.fetchedAt = fetchedAt
    }

    public static let empty = UsageSnapshot(claude: nil, codex: nil, fetchedAt: .distantPast)

    /// Why this agent has no usage to show, or `nil` when it does (or when the agent has no
    /// usage concept at all).
    public func unavailableReason(for agentType: AgentType) -> UsageUnavailableReason? {
        switch agentType {
        case .claudeCode: return claude == nil ? claudeUnavailable : nil
        case .codex: return codex == nil ? codexUnavailable : nil
        case .geminiCLI, .custom: return nil
        }
    }

    /// Whether a fetch was attempted but no agent's usage could be obtained.
    ///
    /// Distinct from "not fetched yet" (a nil snapshot). The UI uses this to stop showing the
    /// loading state rather than waiting forever on something that will not arrive.
    public var isEmpty: Bool { claude == nil && codex == nil }

    /// Picks the single usage percentage that matters most to a session, for the always-visible gauge.
    ///
    /// - Claude Code: prefers the window actually in force (`is_active`), otherwise the highest
    ///   percentage. Looking only at the session window would miss cases where a per-model weekly
    ///   window hits its limit first (e.g. Fable 88% vs. session 86%).
    /// - Codex: prefers primary (roughly 5 hours), then secondary (roughly weekly), then
    ///   the usage-based allowance.
    /// - Gemini CLI / Custom: always `nil`, since there is no way to fetch usage; callers hide the gauge.
    public func primaryUsedPercent(for agentType: AgentType) -> Double? {
        primaryWindow(for: agentType)?.usedPercent
    }

    /// Picks the window to show in the always-visible gauge, falling back to `auto` when the
    /// window named by `metric` does not exist.
    ///
    /// Returns the window rather than just `usedPercent` so callers can also use `severity`
    /// and `resetsAt`.
    public func primaryWindow(
        for agentType: AgentType,
        metric: UsageGaugeMetric = .auto
    ) -> UsageWindow? {
        if metric != .auto, let selected = window(for: agentType, metric: metric) {
            return selected
        }
        return autoWindow(for: agentType)
    }

    /// Resolves a semantic-level window to the per-agent window that corresponds to it.
    private func window(for agentType: AgentType, metric: UsageGaugeMetric) -> UsageWindow? {
        switch agentType {
        case .claudeCode:
            guard let claude else { return nil }
            switch metric {
            case .auto: return nil
            case .session: return claude.session
            case .weekly: return claude.weekAllModels
            case .weeklyModel:
                return claude.weekModels.map(\.window).max { $0.usedPercent < $1.usedPercent }
            }
        case .codex:
            guard let codex else { return nil }
            switch metric {
            case .auto, .weeklyModel: return nil
            case .session: return codex.primary
            case .weekly: return codex.secondary
            }
        case .geminiCLI, .custom:
            return nil
        }
    }

    /// How `auto` chooses.
    ///
    /// - Claude Code: prefers the window actually in force (`is_active`), otherwise the highest
    ///   percentage. Looking only at the session window would miss cases where a per-model weekly
    ///   window hits its limit first (e.g. Fable 88% vs. session 86%).
    /// - Codex: prefers primary (roughly 5 hours), then secondary (roughly weekly), then
    ///   the usage-based allowance.
    private func autoWindow(for agentType: AgentType) -> UsageWindow? {
        switch agentType {
        case .claudeCode:
            guard let claude else { return nil }
            let windows =
                [claude.session, claude.weekAllModels].compactMap { $0 }
                + claude.weekModels.map(\.window)
            guard !windows.isEmpty else { return nil }
            if let active = windows.filter(\.isActive).max(by: { $0.usedPercent < $1.usedPercent }) {
                return active
            }
            return windows.max { $0.usedPercent < $1.usedPercent }
        case .codex:
            return codex?.primary ?? codex?.secondary ?? codex?.individualLimit?.usageWindow
        case .geminiCLI, .custom:
            return nil
        }
    }
}
