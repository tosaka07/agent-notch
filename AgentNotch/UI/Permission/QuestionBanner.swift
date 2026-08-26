import AgentNotchCore
import Defaults
import SwiftUI

/// Answer UI for `AskUserQuestion`. Shows 1-4 questions one at a time, **tab
/// style**.
///
/// The look matches `PermissionBanner`: black ground, thin border, mono
/// uppercase, and glyphs rather than system controls, so it reads as continuous
/// with the detail view's timeline. Selection state is spoken in glyphs too —
/// ◇/◆ for single-select, □/■ for multiSelect. `notchCard` wraps it as **a
/// second surface placed inside the notch panel**: a translucent dark one step
/// lighter than the panel; see `NotchCard`. No status glyph in the headline —
/// the glyph at the top of the panel already shows `!`, and repeating it would
/// read as the same state twice.
/// - The display area always holds one question. Its height varies with the
///   question's content (number of options, text length).
/// - **Selecting alone does not advance.** Both single-select and multiSelect
///   move on only when NEXT / SEND at the bottom is pressed. Sending on tap
///   would turn a mis-tap straight into the final answer with no chance to
///   reconsider.
/// - Single-select replaces the selection; pressing the same option again
///   clears it.
/// - Other (a free-text TextField) works within the same one-question area and
///   advances on Return or the confirm button.
/// - `onAnswer` is called once, with everything, after the last question is
///   answered.
struct QuestionBanner: View {
    let questions: [AskQuestionInfo.Question]
    /// Predicted time at which the hook stops waiting for a response. Drives the
    /// remaining-time display and the local expiry check.
    var expiresAt: Date = .distantFuture
    /// The response path is confirmed expired (the socket already discarded the
    /// pending entry).
    var isExpired: Bool = false
    /// The answer was sent and is waiting for the runtime's resolved event.
    var isSubmitting: Bool = false
    /// Whether Agent Notch owns a response channel or is only observing the
    /// question from a Codex hook/rollout.
    var responseMode: QuestionResponseMode = .direct
    let keyboardInteraction: KeyboardInteractionController
    var onAnswer: ([String: [String]]) -> Void
    /// Available only when the owning terminal can be resolved safely.
    var onRespondInTerminal: (() -> Void)? = nil
    /// Dismisses the expired banner.
    var onDismiss: () -> Void = {}

    /// Response key → set of selected labels. MultiSelect holds
    /// several; single-select holds 0 or 1.
    @State private var selections: [String: Set<String>] = [:]
    /// Response key → the free text typed into Other.
    @State private var otherInputs: [String: String] = [:]
    /// Index of the question currently on screen.
    @State private var currentIndex: Int = 0

    /// Whether the ASCII preview pane is open.
    ///
    /// **Open by default**: a preview-carrying question is one whose options
    /// need visual comparison, so the comparison material should be there the
    /// moment the question appears (matching the CLI, which opens side-by-side
    /// right away). `p` or the badge closes it for whoever wants the full-width
    /// list. While open the question area is a CLI-style side-by-side (list
    /// left, preview right) **inside the question card**: the preview belongs
    /// to the question, so it never leaves the question's surface, and the
    /// banner keeps (almost) its height — the footer and the log behind stay
    /// where they are. Questions without previews render the plain list no
    /// matter what this flag says.
    @State private var showPreview = true
    /// Measured height of the option list while the preview is open; the pane
    /// matches it so the side-by-side reads as one block.
    @State private var optionListHeight: CGFloat = 0
    /// true: forward (slides right to left), false: back (left to right).
    @State private var slideForward = true
    /// The row selected by keyboard. `0..<options.count` are the options;
    /// `options.count` is the Other row.
    @State private var focusedRow = 0
    /// Whether Other's TextField is being edited. Key handling stays out of the
    /// way while it is, so typing wins.
    @FocusState private var isEditingOther: Bool

    @Default(.textSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var scale: CGFloat { textSize.scale }
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    private var currentQuestion: AskQuestionInfo.Question { questions[currentIndex] }
    private var isLastQuestion: Bool { currentIndex == questions.count - 1 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired =
                responseMode == .direct
                && (isExpired || context.date >= expiresAt)
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                if expired {
                    expiredSection
                } else {
                    progressHeader(now: context.date)

                    // One scrolling region for the whole card: the question
                    // text, the options and the preview scroll together.
                    // Scrolling the option list on its own put a scroll view
                    // inside a scroll view, and a drag would land in whichever
                    // one happened to be under the pointer.
                    //
                    // The header and the footer stay outside it, so NEXT / SEND
                    // is always in the same place and always reachable.
                    ScrollView(.vertical) {
                        ZStack {
                            questionSection(currentQuestion)
                                .id(currentQuestion.id)
                                .transition(slideTransition)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Reliably cut off the neighboring question as it slides
                        // past. `clipped` alone can let the first frame of the
                        // transition show outside the bounds.
                        .clipShape(Rectangle())
                    }
                    .frame(maxHeight: maxContentHeight)
                    // Shrink to the content when it is short, so a plain
                    // question does not reserve the full height.
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollBounceBehavior(.basedOnSize)

                    if responseMode == .direct {
                        navigationFooter
                    } else {
                        terminalOnlyFooter
                    }
                }
            }
            // A question just waits to be answered; unlike an approval it does
            // not force an irreversible decision. The semantic color is
            // therefore reserved for expiry ("can no longer be delivered") and
            // the surface stays neutral otherwise. Surface and border are built
            // the same way as the permission banner's.
            .notchCard(
                accent: expired ? DSColors.signalError : DSColors.lineDefault,
                tintsSurface: expired
            )
        }
        // Guards against a mis-tap caused by wherever the mouse happened to be
        // when the banner appeared — same intent as approve/deny.
        .armedAfter()
        .onReceive(keyboardInteraction.commands) { event in
            handleKeyboardCommand(event.command)
        }
        .onChange(of: currentIndex) { _, _ in
            // On a new question, restart from the first row and return the
            // preview to its default (open) — closing it was a choice about
            // the previous question, not this one.
            isEditingOther = false
            focusedRow = 0
            showPreview = true
        }
    }

    // MARK: - Keyboard

    /// Number of selectable rows (options plus Other when the protocol allows it).
    private var rowCount: Int {
        currentQuestion.options.count + (currentQuestion.allowsOther ? 1 : 0)
    }

    private func handleKeyboardCommand(_ command: KeyboardCommand) {
        guard keyboardInteraction.isEngaged,
            keyboardInteraction.context == .question,
            !isEditingOther,
            !isSubmitting
        else { return }

        if responseMode == .terminalOnly {
            switch command {
            case .previousQuestion:
                goToPrevious()
            case .nextQuestion:
                goToNextForViewing()
            case .activate:
                onRespondInTerminal?()
            case .togglePreview where hasAnyPreview:
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showPreview.toggle()
                }
            default:
                break
            }
            return
        }

        switch command {
        case .movePrevious:
            moveFocus(by: -1)
        case .moveNext:
            moveFocus(by: 1)
        case .toggleSelection:
            activateFocusedRow()
        case .previousQuestion:
            goToPrevious()
        case .nextQuestion:
            advanceOrSend()
        case .activate:
            if isExpired || Date() >= expiresAt {
                onDismiss()
            } else {
                advanceOrSend()
            }
        case .togglePreview where hasAnyPreview:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showPreview.toggle()
            }
        case .selectNumber(let number)
        where number >= 1 && number <= currentQuestion.options.count:
            focusedRow = number - 1
            activateFocusedRow()
        default:
            break
        }
    }

    private func moveFocus(by delta: Int) {
        guard rowCount > 0 else { return }
        // Wrap around instead of stopping at the ends. There are only a few
        // options, so cycling beats hitting a dead end.
        focusedRow = (focusedRow + delta + rowCount) % rowCount
    }

    /// Selects the focused row, or starts editing if it is the Other row.
    private func activateFocusedRow() {
        let question = currentQuestion
        if focusedRow < question.options.count {
            select(option: question.options[focusedRow], in: question)
        } else if question.allowsOther {
            isEditingOther = true
        }
    }

    /// Selects or deselects an option. Single-select replaces the one selection.
    private func select(option: AskQuestionInfo.Option, in question: AskQuestionInfo.Question) {
        if question.multiSelect {
            toggleSelection(questionId: question.id, label: option.label)
            return
        }
        if (selections[question.id] ?? []).contains(option.label) {
            selections[question.id] = []
        } else {
            selections[question.id] = [option.label]
            otherInputs[question.id] = ""
        }
    }

    /// With Reduce Motion on, cross-fade with opacity instead of sliding.
    private var slideTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    /// What is shown once the response path has expired. The answer can no
    /// longer be delivered, so instead of options it points the user at the
    /// owning agent surface, making the silent failure visible for both CLI
    /// and desktop sessions.
    private var expiredSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Text(verbatim: L("Response window expired").uppercased())
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(1.6)
                    // Semantic color on the headline too, matching the
                    // permission banner.
                    .foregroundStyle(DSColors.signalError)
                Spacer(minLength: 0)
            }
            Text(
                l10n:
                    "This answer can no longer be delivered here. Respond in the original agent window."
            )
            .font(DSTypography.Native.caption(scale))
            .foregroundStyle(DSColors.inkDim)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                GlyphButton(
                    label: L("Dismiss").uppercased(),
                    shortcut: .returnKey,
                    isProminent: true
                ) { onDismiss() }
                .accessibilityHint(L("Dismisses this expired request"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sub views

    /// Header row: `‹ QUESTION 2/3 ■▪□ ............ 12S`
    ///
    /// **The position (2/3) and the progress glyphs (■▪□) say the same thing in
    /// two forms**, so they sit next to each other. Splitting them to opposite
    /// ends only makes the eye travel and obscures that they correspond. Only
    /// the remaining seconds are set apart, being a different kind of
    /// information: the response deadline.
    private func progressHeader(now: Date) -> some View {
        HStack(spacing: DSSpacing.sm) {
            if questions.count > 1 {
                Button {
                    goToPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: s(9), weight: .semibold))
                        .foregroundStyle(currentIndex == 0 ? DSColors.lineStrong : DSColors.inkDim)
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentIndex == 0)
                .accessibilityLabel(L("Previous question"))
            }

            Text(verbatim: L("Question").uppercased())
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(DSColors.ink.opacity(0.85))

            if questions.count > 1 {
                HStack(spacing: 6) {
                    Text("\(currentIndex + 1)/\(questions.count)")
                        .font(DSTypography.mono(s(9), weight: .semibold))
                        .foregroundStyle(DSColors.inkDim)
                        .monospacedDigit()
                    progressGlyphs
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Question \(currentIndex + 1) of \(questions.count)"))
            }

            Spacer(minLength: 0)

            // As the deadline nears, show the seconds left before the hook falls
            // through to pass-through.
            let remaining = expiresAt.timeIntervalSince(now)
            if remaining < 30, remaining > 0 {
                Text(verbatim: L("\(Int(remaining))s").uppercased())
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(DSColors.signalAlert)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(
                        DSShape.rounded(DSShape.badge)
                            .stroke(DSColors.signalAlert.opacity(0.4), lineWidth: 0.5)
                    )
                    .accessibilityLabel(L("\(Int(remaining)) seconds remaining"))
            }
        }
    }

    /// Shows progress in the task vocabulary: □ unanswered, ▪ in progress,
    /// ■ answered. Working through questions in order is the same activity as a
    /// task board, so it should read the same way.
    private var progressGlyphs: some View {
        HStack(spacing: 3) {
            ForEach(0..<questions.count, id: \.self) { index in
                GlyphView(
                    bitmap: Glyph.task(
                        index < currentIndex ? .done : (index == currentIndex ? .active : .todo),
                        color: index <= currentIndex ? DSColors.ink.opacity(0.8) : DSColors.inkMute
                    ),
                    dot: max(1, s(1.5)),
                    gap: max(0.5, s(0.5))
                )
            }
        }
    }

    @ViewBuilder
    private func questionSection(_ q: AskQuestionInfo.Question) -> some View {
        // Spacing varies per element. The label acts as a heading for the
        // question text, so it sits tight against it; the gap between question
        // and options is wide because that is where reading turns into choosing.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if let hdr = q.header, !hdr.isEmpty {
                    Text(hdr.uppercased())
                        .font(DSTypography.mono(s(8), weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(DSColors.inkDim)
                }
                if q.multiSelect {
                    Text(l10n: "MULTI")
                        .font(DSTypography.mono(s(8)))
                        .tracking(0.6)
                        .foregroundStyle(DSColors.inkMute)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(
                            DSShape.rounded(DSShape.tag)
                                .stroke(DSColors.lineDefault, lineWidth: 0.5)
                        )
                }
            }
            .padding(.bottom, 2)

            // The question text is prose, so it keeps the semantic font — mono
            // uppercase would be hard to read.
            Text(q.question)
                .font(DSTypography.Native.callout(scale))
                .foregroundStyle(DSColors.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, DSSpacing.md)

            if showPreview, hasAnyPreview {
                // CLI-style side-by-side, inside the question card: the option
                // list keeps selection and focus on the left, the focused
                // option's preview fills the right. The preview belongs to the
                // question, so it stays on the question's surface — and because
                // the pane matches the list's height, the banner grows by
                // (almost) nothing: the footer and the log keep their places.
                HStack(alignment: .top, spacing: DSSpacing.sm) {
                    optionList(q)
                        .frame(width: s(220))
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                            optionListHeight = $0
                        }
                    // Match the list's height so the two columns read as one
                    // block, but only as a floor: a taller preview grows the
                    // content and the single outer scroll takes over.
                    previewPane
                        .frame(minHeight: max(optionListHeight, s(120)), alignment: .top)
                }
            } else {
                optionList(q)
            }
        }
    }

    /// How much width the PREVIEW badge needs so the option title wraps before it.
    private static let previewBadgeGutter: CGFloat = 58

    /// Ceiling for the card's scrolling area — the question text, the options
    /// and the preview together.
    ///
    /// The banner is pinned to the bottom of the panel. Without a ceiling it
    /// grows until **NEXT / SEND is pushed off the panel** and the question can
    /// no longer be answered. The panel is a fixed height per mode, so a
    /// constant is enough here.
    private var maxContentHeight: CGFloat { s(290) }

    private func optionList(_ q: AskQuestionInfo.Question) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(q.options.enumerated()), id: \.element.id) { index, opt in
                optionRow(question: q, option: opt, index: index)
            }
            if q.allowsOther {
                // The "Other" row: free text. Any input counts as selected.
                otherRow(question: q)
            }
        }
    }

    @ViewBuilder
    private func optionRow(
        question: AskQuestionInfo.Question,
        option: AskQuestionInfo.Option,
        index: Int
    ) -> some View {
        let questionId = question.id
        let multiSelect = question.multiSelect
        let isSelected = (selections[questionId] ?? []).contains(option.label)
        // The row selected by keyboard. Never shown to someone who only clicks:
        // keys do not arrive unless the panel is the key window, so the marker
        // alone would mean nothing.
        let isFocused = showsKeyHints && focusedRow == index
        // The PREVIEW badge is a *sibling* of the row button, not nested inside
        // its label: SwiftUI flattens a Button nested in another Button's label
        // here (the inner one is neither hit-testable nor exposed to
        // accessibility), so the badge has to live outside. The shared
        // surface/border wraps both so the row still reads as one cell.
        let hasPreview = option.preview?.isEmpty == false
        Button {
            focusedRow = index
            // This only replaces the selection. Advancing waits for NEXT / SEND
            // so there is still room to change one's mind.
            select(option: option, in: question)
        } label: {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                selectionGlyph(multiSelect: multiSelect, selected: isSelected)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(DSTypography.Native.subheadline(scale, weight: .medium))
                        .foregroundStyle(isSelected ? DSColors.ink : DSColors.ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        // Only the title makes room for the badge. The badge is an
                        // overlay, so leaving this out would let the title run under it.
                        .padding(.trailing, hasPreview ? Self.previewBadgeGutter : 0)
                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .font(DSTypography.Native.caption(scale))
                            .foregroundStyle(DSColors.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.sm).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(responseMode == .terminalOnly)
        .accessibilityLabel(option.description.map { "\(option.label). \($0)" } ?? option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The badge sits in an overlay rather than beside the row. As a sibling
        // in the row's HStack it reserved its width down the **whole height** of
        // the row, so every line of the description was ~20% narrower and the
        // space under the badge went unused.
        .overlay(alignment: .topTrailing) {
            if hasPreview {
                previewBadge(index: index)
                    .padding(.top, 8)
                    .padding(.trailing, DSSpacing.sm)
            }
        }
        .background(optionSurface(isSelected: isSelected))
        .overlay(
            DSShape.rounded(DSShape.inset)
                // The border stays legible even when unselected. If the
                // rows blur together, where one option ends and the next
                // begins becomes unreadable.
                .stroke(rowBorder(isSelected: isSelected, isFocused: isFocused), lineWidth: 0.5)
        )
        .clipShape(DSShape.rounded(DSShape.inset))
    }

    @ViewBuilder
    private func otherRow(question: AskQuestionInfo.Question) -> some View {
        let questionId = question.id
        let multiSelect = question.multiSelect
        let binding = Binding<String>(
            get: { otherInputs[questionId] ?? "" },
            set: { otherInputs[questionId] = $0 }
        )
        let hasText = !(otherInputs[questionId] ?? "").isEmpty
        let isFocused = showsKeyHints && focusedRow == question.options.count
        HStack(alignment: .center, spacing: DSSpacing.sm) {
            selectionGlyph(multiSelect: multiSelect, selected: hasText)
            Group {
                if question.isSecret {
                    SecureField(L("Other…"), text: binding)
                } else {
                    TextField(L("Other…"), text: binding)
                }
            }
            .textFieldStyle(.plain)
            .font(DSTypography.Native.subheadline(scale))
            .foregroundStyle(DSColors.ink)
            .focused($isEditingOther)
            .disabled(responseMode == .terminalOnly)
            .onSubmit {
                isEditingOther = false
                advanceOrSend()
            }
        }
        .padding(.horizontal, DSSpacing.sm).padding(.vertical, 7)
        .background(optionSurface(isSelected: hasText))
        .overlay(
            DSShape.rounded(DSShape.inset)
                .stroke(rowBorder(isSelected: hasText, isFocused: isFocused), lineWidth: 0.5)
        )
        .clipShape(DSShape.rounded(DSShape.inset))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Other, free text"))
    }

    private var navigationFooter: some View {
        HStack(spacing: DSSpacing.sm) {
            // Only show the key hints when keys actually arrive — otherwise
            // they would be a lie.
            if showsKeyHints {
                HStack(spacing: DSSpacing.sm) {
                    KeyHintLabel(chord: .verticalArrows, label: L("Move"))
                    KeyHintLabel(chord: .space, label: L("Select"))
                    if hasAnyPreview {
                        KeyHintLabel(chord: .character("P"), label: L("Preview"))
                    }
                    if questions.count > 1 {
                        KeyHintLabel(chord: .horizontalArrows, label: L("Question"))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            // Deliberately no `.defaultAction`: Other's TextField already has
            // onSubmit(Return), and combining the two could fire
            // advanceOrSend() twice for a single Return.
            GlyphButton(
                label: (isLastQuestion ? L("Send") : L("Next")).uppercased(),
                shortcut: .returnKey,
                tint: DSColors.signalDone,
                isProminent: true,
                isEnabled: canSend(currentQuestion),
                isLoading: isSubmitting
            ) {
                advanceOrSend()
            }
        }
    }

    private var terminalOnlyFooter: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(
                l10n:
                    "This question is visible here, but its response channel belongs to Codex. Answer it in the original Codex window."
            )
            .font(DSTypography.Native.caption(scale))
            .foregroundStyle(DSColors.inkDim)
            .fixedSize(horizontal: false, vertical: true)

            if currentIndex < questions.count - 1 || onRespondInTerminal != nil {
                HStack(spacing: DSSpacing.sm) {
                    if currentIndex < questions.count - 1 {
                        GlyphButton(
                            label: L("Next").uppercased(),
                            shortcut: .right
                        ) {
                            goToNextForViewing()
                        }
                    }
                    Spacer(minLength: 0)
                    if let onRespondInTerminal {
                        GlyphButton(
                            label: L("Answer in Terminal").uppercased(),
                            shortcut: .returnKey,
                            isProminent: true
                        ) {
                            onRespondInTerminal()
                        }
                        .accessibilityHint(L("Moves focus to the terminal that owns this question"))
                    }
                }
            }
        }
    }

    // MARK: - Preview pane

    /// Whether this question has any option carrying a preview. By spec previews
    /// only appear on single-select questions, but the check is data-driven.
    private var hasAnyPreview: Bool {
        currentQuestion.options.contains { $0.preview?.isEmpty == false }
    }

    /// Preview for the focused row; nil on the Other row or an option without one.
    private var focusedPreview: String? {
        guard focusedRow < currentQuestion.options.count else { return nil }
        return currentQuestion.options[focusedRow].preview
    }

    /// Toggle badge shown on rows that carry a preview. It is pressable
    /// independently of tapping the row to select it, since SwiftUI gives the
    /// inner button priority in a nested pair.
    private func previewBadge(index: Int) -> some View {
        let isShowing = showPreview && focusedRow == index
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                if isShowing {
                    showPreview = false
                } else {
                    focusedRow = index
                    showPreview = true
                }
            }
        } label: {
            Text(verbatim: L("Preview").uppercased())
                .font(DSTypography.mono(s(7), weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(isShowing ? DSColors.ink : DSColors.inkMute)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .overlay(
                    DSShape.rounded(DSShape.tag)
                        .stroke(isShowing ? DSColors.lineStrong : DSColors.lineDefault, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isShowing ? L("Hide preview") : L("Show preview"))
    }

    /// ASCII preview of the focused option, shown to the right of the option
    /// list. Moving focus swaps only the contents (the height tracks the list,
    /// not the preview), so the card never jolts while ↑↓ walks across rows.
    /// When the focused row has no preview the pane holds a placeholder instead
    /// of collapsing. ASCII art breaks when wrapped, so it is shown unwrapped
    /// with scrolling on both axes.
    private var previewPane: some View {
        Group {
            if let preview = focusedPreview, !preview.isEmpty {
                // Horizontal only. ASCII art needs it, but a vertical scroll
                // here would be the second one inside the card's scroll.
                ScrollView(.horizontal) {
                    Text(preview)
                        .font(DSTypography.mono(s(9)))
                        .foregroundStyle(DSColors.ink.opacity(0.85))
                        .fixedSize()
                        .padding(DSSpacing.sm)
                }
            } else {
                Text(l10n: "No preview for this option")
                    .font(DSTypography.mono(s(9)))
                    .foregroundStyle(DSColors.inkMute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(DSSurfaceFill(.inset))
        .clipShape(DSShape.rounded(DSShape.inset))
        .overlay(
            DSShape.rounded(DSShape.inset)
                .stroke(DSColors.lineFaint, lineWidth: 0.5)
        )
    }

    // MARK: - State management

    /// The row border. Only the keyboard-selected row brightens, more strongly
    /// than a selected row's border. "What is selected" and "where the cursor
    /// is" are different pieces of information, so they are split across the
    /// surface (selection) and the border (focus).
    private func rowBorder(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused { return DSColors.ink.opacity(0.55) }
        return isSelected ? DSColors.lineStrong : DSColors.lineDefault
    }

    /// Whether key hints and the focus marker may be shown. Keys do not arrive
    /// unless the panel is the key window, so showing them otherwise would lie.
    private var showsKeyHints: Bool { keyboardInteraction.isEngaged }

    /// The option surface, made **brighter than the card** so it reads as being
    /// in front.
    ///
    /// The card is glass, so sinking an option in black would push it behind
    /// rather than in front. A sunken control does not invite touch, so a thin
    /// scrim tempers the material's brightness and white is layered on top,
    /// lifting the option one step off the card.
    @ViewBuilder
    private func optionSurface(isSelected: Bool) -> some View {
        DSSurfaceFill(isSelected ? .raisedSelected : .raised)
    }

    /// Speaks the selection state in glyphs: ◇/◆ for single-select, □/■ for
    /// multiSelect. It reuses the vocabulary already established by tasks (□▪■)
    /// and subagents (◆◇), so "outline = unselected, filled = selected" reads
    /// the same across screens.
    private func selectionGlyph(multiSelect: Bool, selected: Bool) -> some View {
        let bitmap: GlyphBitmap =
            multiSelect
            ? Glyph.task(selected ? .done : .todo, color: selected ? DSColors.ink : DSColors.inkDim)
            : (selected
                ? Glyph.subagentRunning(color: DSColors.ink) : Glyph.subagentIdle(color: DSColors.inkDim))
        return GlyphView(bitmap: bitmap, dot: max(1, s(2)), gap: max(0.5, s(1)))
    }

    private func toggleSelection(questionId: String, label: String) {
        var current = selections[questionId] ?? []
        if current.contains(label) {
            current.remove(label)
        } else {
            current.insert(label)
        }
        selections[questionId] = current
    }

    /// Whether the given question has any option selected OR text in Other.
    private func canSend(_ q: AskQuestionInfo.Question) -> Bool {
        let selected = selections[q.id] ?? []
        let other = (otherInputs[q.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !selected.isEmpty || !other.isEmpty
    }

    /// Moves to the next question, or sends all answers on the last one.
    private func advanceOrSend() {
        guard canSend(currentQuestion) else { return }
        if isLastQuestion {
            onAnswer(collectedAnswers())
        } else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                slideForward = true
                currentIndex += 1
            }
        }
    }

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            slideForward = false
            currentIndex -= 1
        }
    }

    private func goToNextForViewing() {
        guard currentIndex < questions.count - 1 else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            slideForward = true
            currentIndex += 1
        }
    }

    /// Builds the answers map to send. Other is appended to the end of the array
    /// as if it were another option.
    private func collectedAnswers() -> [String: [String]] {
        var result: [String: [String]] = [:]
        for q in questions {
            var labels = Array(selections[q.id] ?? [])
            let other = (otherInputs[q.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !other.isEmpty {
                labels.append(other)
            }
            result[q.responseKey] = labels
        }
        return result
    }
}

#Preview("Question Banner") {
    QuestionBanner(
        questions: [
            .init(
                question: "Which approach should we take?",
                header: "Design direction",
                multiSelect: false,
                options: [
                    .init(
                        label: "A: Incremental refactor",
                        description: "Keep the existing API, replace only the internals",
                        preview: """
                            ┌──────────────────────────────┐
                            │ Facade (existing API)         │
                            │   ├─ LegacyImpl   ← phased    │
                            │   └─ NewImpl      ← swap-in   │
                            └──────────────────────────────┘
                            """
                    ),
                    .init(
                        label: "B: Full rewrite",
                        description: "Accept breaking changes and rebuild from scratch",
                        preview: """
                            ┌──────────────────────────────┐
                            │ NewAPI                        │
                            │   └─ NewImpl                  │
                            │ (LegacyImpl removed)          │
                            └──────────────────────────────┘
                            """
                    ),
                ]
            ),
            .init(
                question: "Which files should be included?",
                header: nil,
                multiSelect: true,
                options: [
                    .init(label: "PermissionBanner.swift", description: nil, preview: nil),
                    .init(label: "QuestionBanner.swift", description: nil, preview: nil),
                    .init(label: "SessionDetailView.swift", description: nil, preview: nil),
                ]
            ),
        ],
        keyboardInteraction: KeyboardInteractionController(),
        onAnswer: { _ in }
    )
    .padding(20)
    .frame(width: 460)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}

#Preview("Question Banner (Expired)") {
    QuestionBanner(
        questions: [
            .init(
                question: "Which approach should we take?",
                header: nil,
                multiSelect: false,
                options: [.init(label: "A", description: nil, preview: nil)]
            )
        ],
        isExpired: true,
        keyboardInteraction: KeyboardInteractionController(),
        onAnswer: { _ in },
        onDismiss: {}
    )
    .padding(20)
    .frame(width: 460)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
