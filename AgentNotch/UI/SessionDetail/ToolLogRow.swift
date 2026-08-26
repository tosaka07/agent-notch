import AgentNotchCore
import Defaults
import SwiftUI

/// A single tool call, interleaved into the timeline.
///
/// # Collapse / expand
/// Collapsed to one line by default; a click — or the header's bulk toggle —
/// opens the contents. Same shape as Claude Code itself: the conversation flows
/// uninterrupted, and you look inside a tool only when you need to.
///
/// ```
/// ▸ ● 21:04:02  BASH  pnpm build · 3 lines        ← collapsed (one line)
/// ▾ ● 21:04:02  BASH  pnpm build · 3 lines
///     ┌────────────────────────────┐
///     │ $ pnpm build --filter=web  │            ← expanded
///     │ ▸ tasks: 12 successful     │
///     └────────────────────────────┘
/// ```
///
/// **The dot on the left says what kind of row this is**, and the contents —
/// code, table, diff — sit on black as raw monospaced information. The dot's
/// color distinguishes success, diff, search, error, and running.
struct ToolLogRow: View {
    /// A run of consecutive calls to the same tool. **Always at least one**; a
    /// single entry is just an ordinary row. Deciding what to group belongs to
    /// `TimelineRow.rows(from:)`; this only draws.
    let entries: [ToolLogEntry]
    /// The header's bulk toggle expands or collapses everything. Per-row
    /// toggling overrides it.
    let expandAll: Bool

    init(entries: [ToolLogEntry], expandAll: Bool) {
        self.entries = entries
        self.expandAll = expandAll
    }

    init(entry: ToolLogEntry, expandAll: Bool) {
        self.init(entries: [entry], expandAll: expandAll)
    }

    @State private var localExpanded: Bool?
    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var isExpanded: Bool { localExpanded ?? expandAll }

    /// The entry that represents the header. Name and kind are shared across a
    /// run, so the first one is enough.
    private var entry: ToolLogEntry { entries[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                localExpanded = !isExpanded
            } label: {
                headerLine
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.name) \(entry.resultSummary)")
            .accessibilityValue(isExpanded ? L("Expanded") : L("Collapsed"))
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                // A grouped run opens entry by entry. Knowing only the count
                // does not tell you what was read or what was executed.
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(entries) { item in
                        if entries.count > 1, !detailText(item).isEmpty {
                            Text(detailText(item))
                                .font(DSTypography.mono(s(9)))
                                .tracking(0.8)
                                .foregroundStyle(DSColors.inkMute)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        contentBlock(item)
                    }
                }
                .padding(.leading, TimelineMetrics.contentIndent)
            }
        }
        // Discard per-row state when the bulk toggle flips, so expand-all and
        // collapse-all actually take effect.
        .onChange(of: expandAll) { _, _ in localExpanded = nil }
    }

    // MARK: - Header

    /// `▸ BASH ×3  pnpm build · 12 lines`
    ///
    /// **No dot here.** Only messages (`ChatMessageView`) carry one; tool rows
    /// step back with the secondary text color. Tool rows make up most of the
    /// timeline, so a dot on every one of them would stop being a marker at all.
    /// Errors and running calls are the exception, marked in semantic color.
    ///
    /// The dot's width (6) is still reserved, keeping this vertically aligned
    /// with the message labels.
    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: TimelineMetrics.spacing) {
            // The same column as a message's dot. A separate box would split
            // the vertical streak in two.
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: s(7), weight: .semibold))
                .foregroundStyle(DSColors.inkMute)
                .frame(width: TimelineMetrics.marker)

            Text(entry.name.uppercased())
                .foregroundStyle(nameColor)

            if entries.count > 1 {
                Text("×\(entries.count)")
                    .foregroundStyle(DSColors.inkMute)
            }

            Text(detailText(entry))
                .foregroundStyle(DSColors.inkMute)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .font(DSTypography.mono(s(9)))
        .tracking(0.8)
        .contentShape(Rectangle())
    }

    /// Color of the tool name. Secondary by default, one step back from a
    /// message. Errors and running calls take a semantic color so trouble is
    /// noticeable while still collapsed.
    private var nameColor: Color {
        if entries.contains(where: \.isError) { return DSColors.signalError }
        if entries.contains(where: { $0.output == nil }) { return DSColors.signalAlert }
        return DSColors.inkDim
    }

    /// Detail to the right of the header, joining the input and result summaries
    /// with `·`.
    private func detailText(_ entry: ToolLogEntry) -> String {
        var parts: [String] = []
        if entry.kind == .command, let command = entry.command, !command.isEmpty {
            parts.append(command)
        } else if !entry.inputSummary.isEmpty {
            parts.append(entry.inputSummary)
        }
        if entry.output == nil {
            parts.append(L("running"))
        } else if !entry.resultSummary.isEmpty {
            parts.append(entry.resultSummary)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Content block

    @ViewBuilder
    private func contentBlock(_ entry: ToolLogEntry) -> some View {
        Group {
            switch entry.kind {
            case .command: commandBlock(entry)
            case .diff: diffBlock(entry)
            case .table, .text: outputBlock(entry)
            }
        }
    }

    /// `$ command` plus its output.
    private func commandBlock(_ entry: ToolLogEntry) -> some View {
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
                outputLinesView(entry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A diff with color behind the `−` / `+` lines.
    @ViewBuilder
    private func diffBlock(_ entry: ToolLogEntry) -> some View {
        if let diff = entry.diff, !diff.files.isEmpty {
            let displayedFiles = displayedDiffFiles(diff)
            let displayedLineCount = displayedFiles.reduce(0) { $0 + $1.lineIndices.count }
            let changedLineCount = entry.removedLines.count + entry.addedLines.count

            blockContainer(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayedFiles.enumerated()), id: \.offset) { _, displayed in
                        DiffFileBlock(
                            file: displayed.file,
                            displayedLineIndices: displayed.lineIndices,
                            fontSize: s(Self.blockFontSize)
                        )
                    }
                    if changedLineCount > displayedLineCount {
                        Text("… \(changedLineCount - displayedLineCount) more lines")
                            .font(DSTypography.mono(s(Self.blockFontSize)))
                            .foregroundStyle(DSColors.inkMute)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            outputBlock(entry)
        }
    }

    private struct DisplayedDiffFile {
        let file: ToolDiffFile
        let lineIndices: [Int]
    }

    /// Applies the existing eight-lines-per-side limit across all files while
    /// retaining each selected line's position in its full file snapshot.
    private func displayedDiffFiles(_ diff: ToolDiff) -> [DisplayedDiffFile] {
        var removedCount = 0
        var addedCount = 0
        var result: [DisplayedDiffFile] = []

        for file in diff.files {
            var indices: [Int] = []
            for (index, line) in file.lines.enumerated() {
                switch line.kind {
                case .context:
                    continue
                case .removed where removedCount < Self.maxDiffLines:
                    removedCount += 1
                    indices.append(index)
                case .added where addedCount < Self.maxDiffLines:
                    addedCount += 1
                    indices.append(index)
                default:
                    continue
                }
            }
            if !indices.isEmpty {
                result.append(DisplayedDiffFile(file: file, lineIndices: indices))
            }
        }
        return result
    }

    /// Prints the output verbatim in monospace, for tables and everything else.
    @ViewBuilder
    private func outputBlock(_ entry: ToolLogEntry) -> some View {
        if !outputLines(entry).isEmpty {
            blockContainer {
                outputLinesView(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func outputLinesView(_ entry: ToolLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(outputLines(entry), id: \.self) { line in
                Text(line)
                    .foregroundStyle(
                        entry.isError ? DSColors.signalError.opacity(0.85) : DSColors.ink.opacity(0.6)
                    )
                    .textSelection(.enabled)
            }
        }
    }

    /// Font size for the surfaces that show values: command, output, diff.
    ///
    /// Larger than the header (9) to keep code readable, but **the contents are
    /// supporting information you open only when needed**, so matching the
    /// conversation body (11) would assert too much. Ten splits the difference.
    private static let blockFontSize: CGFloat = 10

    private static let maxOutputLines = 12
    private static let maxDiffLines = 8

    /// Output tends to run long, so the head is shown and the rest reported as a
    /// count. The full text is available in the original terminal.
    private func outputLines(_ entry: ToolLogEntry) -> [String] {
        guard let output = entry.output else { return [] }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count <= Self.maxOutputLines { return lines }
        return Array(lines.prefix(Self.maxOutputLines)) + [
            "… \(lines.count - Self.maxOutputLines) more lines"
        ]
    }

    private func blockContainer<Content: View>(
        padded: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(DSTypography.mono(s(Self.blockFontSize)))
            .padding(.horizontal, padded ? 10 : 0)
            .padding(.vertical, padded ? 8 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The surface that shows values, with the same texture as a code
            // block inside a message or the command block on an approval.
            .background(DSSurfaceFill(.inset))
            .overlay(
                DSShape.rounded(DSShape.inset)
                    .stroke(DSColors.lineFaint, lineWidth: 0.5)
            )
            .clipShape(DSShape.rounded(DSShape.inset))
    }
}

/// Highlights one file lazily when its expanded diff enters the view.
private struct DiffFileBlock: View {
    let file: ToolDiffFile
    let displayedLineIndices: [Int]
    let fontSize: CGFloat

    @Environment(\.codeHighlighter) private var highlighter
    @State private var highlightedLines: [Int: AttributedString] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let path = file.path, !path.isEmpty {
                Text(path)
                    .font(DSTypography.mono(fontSize * 0.9))
                    .foregroundStyle(DSColors.inkMute)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DSColors.ink.opacity(0.04))
            }

            ForEach(displayedLineIndices, id: \.self) { index in
                let line = file.lines[index]
                switch line.kind {
                case .removed:
                    diffLine("−", line: line.text, index: index, color: DSColors.signalError)
                case .added:
                    diffLine("+", line: line.text, index: index, color: DSColors.signalDone)
                case .context:
                    EmptyView()
                }
            }
        }
        .task(id: file) {
            await loadHighlighting()
        }
    }

    private func diffLine(
        _ marker: String,
        line: String,
        index: Int,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(marker)
                .foregroundStyle(color.opacity(0.85))
                .frame(width: 8, alignment: .leading)
            Text(highlightedLines[index] ?? AttributedString(line.isEmpty ? " " : line))
                .foregroundStyle(DSColors.ink.opacity(0.8))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(DSTypography.mono(fontSize))
        .padding(.horizontal, 10)
        .background(color.opacity(0.1))
    }

    private func loadHighlighting() async {
        highlightedLines = [:]
        let plan = DiffHighlightPlan(file: file)
        async let oldCode = highlighter.highlight(
            CodeHighlightRequest(
                source: plan.oldSource,
                languageHint: file.path.map(CodeLanguageHint.filePath)
            )
        )
        async let newCode = highlighter.highlight(
            CodeHighlightRequest(
                source: plan.newSource,
                languageHint: file.path.map(CodeLanguageHint.filePath)
            )
        )
        let (oldResult, newResult) = await (oldCode, newCode)
        guard !Task.isCancelled else { return }

        var mapped: [Int: AttributedString] = [:]
        for index in displayedLineIndices {
            switch file.lines[index].kind {
            case .removed:
                if let sourceIndex = plan.oldLineIndexByDiffLine[index],
                    oldResult.lines.indices.contains(sourceIndex)
                {
                    mapped[index] = oldResult.lines[sourceIndex]
                }
            case .added:
                if let sourceIndex = plan.newLineIndexByDiffLine[index],
                    newResult.lines.indices.contains(sourceIndex)
                {
                    mapped[index] = newResult.lines[sourceIndex]
                }
            case .context:
                break
            }
        }
        highlightedLines = mapped
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
    let run = (0..<3).map { index in
        ToolLogEntry(
            id: "r\(index)", name: "Read", timestamp: .now,
            inputSummary: "AgentNotch/UI/Glyph\(index).swift",
            output: "line a\nline b", isError: false, kind: .text
        )
    }
    return VStack(alignment: .leading, spacing: 10) {
        ForEach(entries) { ToolLogRow(entry: $0, expandAll: false) }
        ToolLogRow(entries: run, expandAll: false)
        Divider()
        ForEach(entries) { ToolLogRow(entry: $0, expandAll: true) }
        ToolLogRow(entries: run, expandAll: true)
    }
    .padding(16)
    .frame(width: 600)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
