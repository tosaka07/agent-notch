import AgentNotchCore
import Defaults
import SwiftUI

/// タイムラインに混ぜて出すツール実行 1 件（Claude Design モック 3a のログ行）。
///
/// # 畳む / 開く
/// 既定は 1 行に畳んでおき、クリック（またはヘッダーの一括トグル）で中身を開く。
/// Claude Code 本体と同じ「会話の流れを乱さず、必要なときだけツールの中身を見る」形。
///
/// ```
/// ▸ ● 21:04:02  BASH  pnpm build · 3 lines        ← 畳んだ状態（1 行）
/// ▾ ● 21:04:02  BASH  pnpm build · 3 lines
///     ┌────────────────────────────┐
///     │ $ pnpm build --filter=web  │            ← 開いた状態
///     │ ▸ tasks: 12 successful     │
///     └────────────────────────────┘
/// ```
///
/// **左のドットが行の種類を語り**、中身（コード / テーブル / diff）は等幅の素の情報として
/// 黒地に置く。ドットの色は成功 / 差分 / 検索 / エラー / 実行中で変える。
struct ToolLogRow: View {
    let entry: ToolLogEntry
    /// ヘッダーの一括トグルで全部開く / 畳む。個別の開閉はこれを上書きする。
    let expandAll: Bool

    @State private var localExpanded: Bool?
    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var isExpanded: Bool { localExpanded ?? expandAll }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                localExpanded = !isExpanded
            } label: {
                headerLine
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.name) \(entry.resultSummary)")
            .accessibilityValue(isExpanded ? "展開" : "折りたたみ")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                contentBlock
                    .padding(.leading, 16)
            }
        }
        // 一括トグルが切り替わったら個別の開閉状態は捨てる（全部開く / 全部畳むが効くように）。
        .onChange(of: expandAll) { _, _ in localExpanded = nil }
    }

    // MARK: - Header

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: s(7), weight: .semibold))
                .foregroundStyle(DSColors.inkMute)
                .frame(width: 8)

            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            if let timestamp = entry.timestamp {
                Text(Self.timeFormatter.string(from: timestamp))
                    .foregroundStyle(DSColors.inkMute)
            }
            Text(entry.name.uppercased())
                .foregroundStyle(DSColors.ink.opacity(0.7))
            Text(detailText)
                .foregroundStyle(DSColors.inkMute)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(DSTypography.mono(s(9)))
        .tracking(0.8)
        .contentShape(Rectangle())
    }

    /// 行の種類を色で語るドット。成功は白、差分は cyan、検索は緑、エラーは赤、実行中は amber。
    private var dotColor: Color {
        if entry.isError { return DSColors.signalError }
        if entry.output == nil { return DSColors.signalAlert }
        switch entry.kind {
        case .diff: return DSColors.signalThinking
        case .table: return DSColors.signalDone
        case .command, .text: return DSColors.ink.opacity(0.75)
        }
    }

    /// 見出し右側の補足。入力の要約と結果の要約を `·` で繋ぐ。
    private var detailText: String {
        var parts: [String] = []
        if entry.kind == .command, let command = entry.command, !command.isEmpty {
            parts.append(command)
        } else if !entry.inputSummary.isEmpty {
            parts.append(entry.inputSummary)
        }
        if entry.output == nil {
            parts.append("実行中")
        } else if !entry.resultSummary.isEmpty {
            parts.append(entry.resultSummary)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Content block

    @ViewBuilder
    private var contentBlock: some View {
        switch entry.kind {
        case .command: commandBlock
        case .diff: diffBlock
        case .table, .text: outputBlock
        }
    }

    /// `$ command` + 出力。
    private var commandBlock: some View {
        blockContainer {
            VStack(alignment: .leading, spacing: 1) {
                if let command = entry.command, !command.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Text("$")
                            .foregroundStyle(DSColors.inkMute)
                        Text(command)
                            .foregroundStyle(DSColors.ink)
                            .textSelection(.enabled)
                    }
                }
                outputLinesView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `−` / `+` 行に色を敷いた差分。
    @ViewBuilder
    private var diffBlock: some View {
        if entry.removedLines.isEmpty, entry.addedLines.isEmpty {
            outputBlock
        } else {
            blockContainer(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entry.removedLines.prefix(Self.maxDiffLines).enumerated()), id: \.offset) { _, line in
                        diffLine("−", line, color: DSColors.signalError)
                    }
                    ForEach(Array(entry.addedLines.prefix(Self.maxDiffLines).enumerated()), id: \.offset) { _, line in
                        diffLine("+", line, color: DSColors.signalDone)
                    }
                    if entry.removedLines.count + entry.addedLines.count > Self.maxDiffLines * 2 {
                        Text("…")
                            .font(DSTypography.mono(s(11)))
                            .foregroundStyle(DSColors.inkMute)
                            .padding(.horizontal, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func diffLine(_ marker: String, _ line: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(marker)
                .foregroundStyle(color.opacity(0.85))
                .frame(width: 8, alignment: .leading)
            Text(line.isEmpty ? " " : line)
                .foregroundStyle(DSColors.ink.opacity(0.8))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(DSTypography.mono(s(11)))
        .padding(.horizontal, 10)
        .background(color.opacity(0.1))
    }

    /// 出力をそのまま等幅で出す（テーブル / その他）。
    @ViewBuilder
    private var outputBlock: some View {
        if !outputLines.isEmpty {
            blockContainer {
                outputLinesView
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var outputLinesView: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(outputLines, id: \.self) { line in
                Text(line)
                    .foregroundStyle(entry.isError ? DSColors.signalError.opacity(0.85) : DSColors.ink.opacity(0.6))
                    .textSelection(.enabled)
            }
        }
    }

    private static let maxOutputLines = 12
    private static let maxDiffLines = 8

    /// 出力は長くなりがちなので頭を見せて残りは件数だけ伝える（全文は元のターミナルで見る）。
    private var outputLines: [String] {
        guard let output = entry.output else { return [] }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count <= Self.maxOutputLines { return lines }
        return Array(lines.prefix(Self.maxOutputLines)) + ["… \(lines.count - Self.maxOutputLines) more lines"]
    }

    private func blockContainer<Content: View>(
        padded: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(DSTypography.mono(s(11)))
            .padding(.horizontal, padded ? 10 : 0)
            .padding(.vertical, padded ? 8 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DSColors.lineFaint, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview("Tool Log Rows") {
    let entries = [
        ToolLogEntry(
            id: "1", name: "Bash", timestamp: .now, inputSummary: "pnpm build",
            command: "pnpm build --filter=web",
            output: "▸ tasks: 12 successful, 0 failed", isError: false, kind: .command
        ),
        ToolLogEntry(
            id: "2", name: "Grep", timestamp: .now, inputSummary: "DSColors",
            output: "DSColors.swift\nDSSpacing.swift\nPixelGrid.swift", isError: false, kind: .table
        ),
        ToolLogEntry(
            id: "3", name: "Edit", timestamp: .now, inputSummary: "DSSpacing.swift",
            removedLines: ["static let md: CGFloat = 12"],
            addedLines: ["static let md = s(12)", "static let dot: CGFloat = 2"],
            output: "", isError: false, kind: .diff
        ),
    ]
    return VStack(alignment: .leading, spacing: 10) {
        ForEach(entries) { ToolLogRow(entry: $0, expandAll: false) }
        Divider()
        ForEach(entries) { ToolLogRow(entry: $0, expandAll: true) }
    }
    .padding(16)
    .frame(width: 600)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
