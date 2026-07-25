import AgentNotchCore
import Defaults
import SwiftUI

/// ExpandedPageView 下部の折りたたみ USAGE セクション。
/// Claude Code の `/usage` 相当（session / week(all models) / week(model)）と
/// Codex の rate limit（5h / weekly）をピクセル調バーで表示する。
struct UsageSectionView: View {
    let snapshot: UsageSnapshot?

    @Default(.usageSectionCollapsed) private var isCollapsed

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 4) {
            header
            if !isCollapsed {
                content
                    .padding(.top, 2)
                    .padding(.bottom, 8)
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DSColors.inkDim)
                    .frame(width: 10)
                Text("USAGE")
                    .font(DSTypography.mono(10, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(DSColors.inkDim)
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        let claude = snapshot?.claude
        let codex = snapshot?.codex

        if claude == nil && codex == nil {
            Text("使用量を取得できませんでした")
                .font(DSTypography.mono(9))
                .foregroundStyle(DSColors.inkMute)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let claude {
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
                if let codex {
                    if let primary = codex.primary {
                        row(label: "CODEX · 5H", window: primary)
                    }
                    if let secondary = codex.secondary {
                        row(label: "CODEX · WEEKLY", window: secondary)
                    }
                    if codex.primary == nil, codex.secondary == nil {
                        Text("Codex: 従量課金プランのため rate limit なし")
                            .font(DSTypography.mono(9))
                            .foregroundStyle(DSColors.inkMute)
                    }
                }
            }
        }
    }

    private func row(label: String, window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(DSTypography.mono(9, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(DSColors.inkDim)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(DSTypography.mono(9, weight: .semibold))
                    .foregroundStyle(DSColors.ink)
            }
            UsageBar(usedPercent: window.usedPercent)
            if let resetsAt = window.resetsAt {
                Text("Resets \(Self.timeFormatter.string(from: resetsAt))")
                    .font(DSTypography.mono(8))
                    .foregroundStyle(DSColors.inkMute)
            }
        }
    }
}
