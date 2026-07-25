import Foundation

/// 使用量の深刻度。API の `severity`（`normal` / `warning` / `critical`）に対応する。
/// 自前のしきい値（70%/90%）より API の判断を優先できるようにするために保持する。
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

/// 単一の使用量ウィンドウ（例: セッション5時間枠、週次枠）。
/// Claude / Codex 共通で使う agent 非依存の表現。
public struct UsageWindow: Sendable, Equatable {
    /// 0〜100 の使用率。
    public let usedPercent: Double
    /// リセット予定時刻。取得できない場合は nil。
    public let resetsAt: Date?
    /// API が返す深刻度。取得できない場合は nil（UI 側が使用率から判断する）。
    public let severity: UsageSeverity?
    /// 現在この枠が実際に効いているか（`limits[].is_active`）。複数枠のうちどれが
    /// 今のボトルネックかを示す。
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

/// モデル別の週次枠。
///
/// モデル名は `limits[].scope.model.display_name`（例: "Fable", "Opus"）から取る。
/// 旧来の `seven_day_<model>` キーは現在のレスポンスでは全て null になっており、
/// モデル別の実データは `limits` 配列にしか現れない。
public struct ModelUsageWindow: Sendable, Equatable, Identifiable {
    public let modelLabel: String
    public let window: UsageWindow

    public var id: String { modelLabel }

    public init(modelLabel: String, window: UsageWindow) {
        self.modelLabel = modelLabel
        self.window = window
    }
}

/// 追加クレジット（従量課金の上乗せ枠）の状況。`extra_usage` / `spend` から取る。
public struct ExtraUsageInfo: Sendable, Equatable {
    /// クレジット利用が有効か。
    public let isEnabled: Bool
    /// 使用済み金額（通貨単位。`spend.used.amount_minor` を `exponent` で割った値）。
    public let usedAmount: Double?
    /// 上限金額。無制限・未設定なら nil。
    public let limitAmount: Double?
    /// 残高。
    public let balanceAmount: Double?
    public let currency: String?
    /// 使用率（%）。
    public let usedPercent: Double?
    /// 無効な理由（`out_of_credits` 等）。
    public let disabledReason: String?
    /// 上限に達しているか。
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

    /// 表示する価値があるか（クレジットが有効、または残高・使用額が存在する）。
    public var hasContent: Bool {
        isEnabled || (usedAmount ?? 0) > 0 || (balanceAmount ?? 0) > 0 || limitAmount != nil
    }
}

/// Claude Code の `/usage` 相当のスナップショット。
/// `api.anthropic.com/api/oauth/usage`（undocumented）のレスポンスから得る。
public struct ClaudeUsageSnapshot: Sendable, Equatable {
    /// Current session（5 時間枠）
    public let session: UsageWindow?
    /// Current week (all models)（7 日枠）
    public let weekAllModels: UsageWindow?
    /// Current week のモデル別枠（複数返る）。
    public let weekModels: [ModelUsageWindow]
    /// 追加クレジット（従量課金）の状況。サブスクのみの環境では大半が nil。
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

/// Codex CLI の rate limit スナップショット。
/// rollout jsonl の `token_count` イベント（`rate_limits`）から得る。
public struct CodexUsageSnapshot: Sendable, Equatable {
    /// primary window（5 時間相当）
    public let primary: UsageWindow?
    /// secondary window（週次相当）
    public let secondary: UsageWindow?
    /// "plus" / "pro" / "business" など。usage-based プランでは各 window が nil になりうる。
    public let planType: String?

    public init(primary: UsageWindow?, secondary: UsageWindow?, planType: String?) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

/// 常時表示ゲージにどの枠を出すか（設定から選択）。
///
/// エージェントごとに枠の呼び名が違う（Claude は session / week、Codex は primary /
/// secondary）ため、**「5 時間相当」「週相当」という意味のレベル**で抽象化して選ばせる。
/// 選んだ枠がそのエージェントに存在しない場合は `auto` にフォールバックする
/// （設定のせいでゲージが消えるのは、設定の副作用として理不尽なため）。
public enum UsageGaugeMetric: String, Sendable, CaseIterable {
    /// 今いちばん逼迫している枠を自動で選ぶ（既定）。
    case auto
    /// セッション枠（Claude: current session / Codex: primary 5h）。
    case session
    /// 週次の全モデル枠（Claude: current week all models / Codex: secondary）。
    case weekly
    /// モデル別週次枠のうち最も高いもの（Claude のみ。Codex には無いので auto に落ちる）。
    case weeklyModel
}

/// UI に渡す集約スナップショット。取得できなかった agent は nil のまま。
public struct UsageSnapshot: Sendable, Equatable {
    public let claude: ClaudeUsageSnapshot?
    public let codex: CodexUsageSnapshot?
    public let fetchedAt: Date

    public init(claude: ClaudeUsageSnapshot?, codex: CodexUsageSnapshot?, fetchedAt: Date) {
        self.claude = claude
        self.codex = codex
        self.fetchedAt = fetchedAt
    }

    public static let empty = UsageSnapshot(claude: nil, codex: nil, fetchedAt: .distantPast)

    /// 取得を試みた結果、どのエージェントの使用量も得られなかったか。
    ///
    /// 「まだ取得していない（snapshot が nil）」と区別するために使う。UI はこれを見て
    /// ローディング表示を打ち切る（取得できないものを待たせ続けないため）。
    public var isEmpty: Bool { claude == nil && codex == nil }

    /// 常時表示ゲージ用に「そのセッションが最も気にすべき使用率」を 1 つ選ぶ。
    ///
    /// - Claude Code: **実際に効いている（`is_active`）枠を優先**し、無ければ最も使用率が
    ///   高い枠を選ぶ。session だけを見ると、モデル別週次枠が先に上限に当たっている
    ///   ケース（Fable 88% > session 86% 等）を見落とすため。
    /// - Codex: primary（5 時間相当）を優先し、無ければ secondary（週次相当）。
    /// - Gemini CLI / Custom: 使用量取得手段が無いため常に `nil`（呼び出し側はゲージを非表示にする）。
    public func primaryUsedPercent(for agentType: AgentType) -> Double? {
        primaryWindow(for: agentType)?.usedPercent
    }

    /// 常時表示ゲージに出す枠を 1 つ選ぶ。`metric` で指定した枠が無ければ `auto` に落とす。
    ///
    /// `usedPercent` だけでなく枠そのものを返すのは、呼び出し側が `severity` /
    /// `resetsAt` も使えるようにするため。
    public func primaryWindow(
        for agentType: AgentType,
        metric: UsageGaugeMetric = .auto
    ) -> UsageWindow? {
        if metric != .auto, let selected = window(for: agentType, metric: metric) {
            return selected
        }
        return autoWindow(for: agentType)
    }

    /// 指定した意味レベルの枠を、エージェントごとの呼び名に解決する。
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

    /// `auto` の選び方。
    ///
    /// - Claude Code: **実際に効いている（`is_active`）枠を優先**し、無ければ最も使用率が
    ///   高い枠を選ぶ。session だけを見ると、モデル別週次枠が先に上限に当たっている
    ///   ケース（Fable 88% > session 86% 等）を見落とすため。
    /// - Codex: primary（5 時間相当）を優先し、無ければ secondary（週次相当）。
    private func autoWindow(for agentType: AgentType) -> UsageWindow? {
        switch agentType {
        case .claudeCode:
            guard let claude else { return nil }
            let windows = [claude.session, claude.weekAllModels].compactMap { $0 }
                + claude.weekModels.map(\.window)
            guard !windows.isEmpty else { return nil }
            if let active = windows.filter(\.isActive).max(by: { $0.usedPercent < $1.usedPercent }) {
                return active
            }
            return windows.max { $0.usedPercent < $1.usedPercent }
        case .codex:
            return codex?.primary ?? codex?.secondary
        case .geminiCLI, .custom:
            return nil
        }
    }
}
