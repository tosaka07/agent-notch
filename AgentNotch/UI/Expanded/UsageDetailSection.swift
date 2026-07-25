import AgentNotchCore
import SwiftUI

/// `ExpandedPageView`（セッション一覧）のトップバー左翼 `UsageGauge` から開く使用量の詳細。
///
/// 左翼の `UsageGauge` が「今どれくらいか」の一点情報だけを見せるのに対し、こちらは
/// 開いて初めて見える詳細: Claude Code の `/usage` 相当（session / week (all models) /
/// week (model)）、Codex の rate limit（5h / weekly）をウィンドウ単位で内訳表示する。
///
/// 一覧画面はどの `agentType` のセッションが並んでいるか一定しないため、`agentType` は
/// `nil`（デフォルト）にすると Claude / Codex 両方（取得できた方）を並べて見せる。
/// 特定のエージェントだけに絞りたい場合のみ `agentType` を指定する。
///
/// パネル内部の表示なので #37 の方針どおり `DSTypography.Native` 等のネイティブトークンを使う
/// （`UsageGauge` 本体とは違い、独自ピクセル言語の対象外）。
///
/// 将来 API コスト推移チャートを追加する場合は、`claudeContent` / `codexContent` の
/// 末尾に新しいセクションを足す形で拡張できるようにしてある。
struct UsageDetailSection: View {
    var agentType: AgentType?
    let snapshot: UsageSnapshot?
    var scale: CGFloat = 1

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        if let agentType {
            content(for: agentType)
        } else {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if snapshot?.claude != nil {
                    claudeContent
                }
                if snapshot?.codex != nil {
                    codexContent
                }
                if snapshot?.claude == nil, snapshot?.codex == nil {
                    unavailable(reason: "使用量を取得できませんでした")
                }
            }
        }
    }

    @ViewBuilder
    private func content(for agentType: AgentType) -> some View {
        switch agentType {
        case .claudeCode:
            claudeContent
        case .codex:
            codexContent
        case .geminiCLI, .custom:
            unavailable(reason: "\(agentType.displayName) は使用量を取得できません")
        }
    }

    @ViewBuilder
    private var claudeContent: some View {
        if let claude = snapshot?.claude {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let session = claude.session {
                    row(label: "CURRENT SESSION", window: session)
                }
                if let weekAllModels = claude.weekAllModels {
                    row(label: "CURRENT WEEK (ALL MODELS)", window: weekAllModels)
                }
                if let weekModel = claude.weekModel {
                    row(
                        label: "CURRENT WEEK (\(claude.weekModelLabel?.uppercased() ?? "MODEL"))",
                        window: weekModel
                    )
                }
            }
        } else {
            unavailable(reason: "使用量を取得できませんでした")
        }
    }

    @ViewBuilder
    private var codexContent: some View {
        if let codex = snapshot?.codex {
            if codex.primary == nil, codex.secondary == nil {
                unavailable(reason: "従量課金プランのため rate limit なし")
            } else {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    if let primary = codex.primary {
                        row(label: "CODEX · 5H", window: primary)
                    }
                    if let secondary = codex.secondary {
                        row(label: "CODEX · WEEKLY", window: secondary)
                    }
                }
            }
        } else {
            unavailable(reason: "使用量を取得できませんでした")
        }
    }

    private func unavailable(reason: String) -> some View {
        Text(reason)
            .font(DSTypography.Native.caption(scale))
            .foregroundStyle(.tertiary)
    }

    private func row(label: String, window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(label)
                    .font(DSTypography.Native.monoCaption2(scale, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(DSTypography.Native.monoCaption(scale, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            UsageBar(usedPercent: window.usedPercent)
            if let resetsAt = window.resetsAt {
                Text("Resets \(Self.timeFormatter.string(from: resetsAt))")
                    .font(DSTypography.Native.caption2(scale))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview("Usage Detail Section - Both") {
    UsageDetailSection(
        snapshot: UsageSnapshot(
            claude: ClaudeUsageSnapshot(
                session: UsageWindow(usedPercent: 42, resetsAt: .now.addingTimeInterval(3600)),
                weekAllModels: UsageWindow(usedPercent: 78, resetsAt: .now.addingTimeInterval(86400 * 3)),
                weekModel: UsageWindow(usedPercent: 95, resetsAt: .now.addingTimeInterval(86400 * 3)),
                weekModelLabel: "opus"
            ),
            codex: CodexUsageSnapshot(
                primary: UsageWindow(usedPercent: 20, resetsAt: .now.addingTimeInterval(1800)),
                secondary: UsageWindow(usedPercent: 55, resetsAt: .now.addingTimeInterval(86400 * 5)),
                planType: "plus"
            ),
            fetchedAt: .now
        )
    )
    .padding(16)
    .frame(width: 280)
}

#Preview("Usage Detail Section - Codex only") {
    UsageDetailSection(
        agentType: .codex,
        snapshot: UsageSnapshot(
            claude: nil,
            codex: CodexUsageSnapshot(
                primary: UsageWindow(usedPercent: 20, resetsAt: .now.addingTimeInterval(1800)),
                secondary: UsageWindow(usedPercent: 55, resetsAt: .now.addingTimeInterval(86400 * 5)),
                planType: "plus"
            ),
            fetchedAt: .now
        )
    )
    .padding(16)
    .frame(width: 280)
}
