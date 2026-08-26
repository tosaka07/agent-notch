import AgentNotchCore
import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

/// Where the first-run flow currently is.
///
/// The tour (`welcome` … `connect`) is reading; `consent` is the only decision; `installing` and
/// `ready` are outcomes. `blocked` is not part of the sequence — it is where a relaunch lands
/// after the disclosure was read and the install declined.
enum OnboardingStep: Equatable, CaseIterable {
    case welcome
    case sessions
    case permissions
    case questions
    case usage
    case connect
    case consent
    case installing
    case ready
    case blocked

    /// The explanatory pages, in order. Only these are counted by the progress ticks.
    static let tour: [OnboardingStep] = [
        .welcome, .sessions, .permissions, .questions, .usage, .connect,
    ]

    var tourIndex: Int? { Self.tour.firstIndex(of: self) }
}

/// The required first-run flow.
///
/// # One page, one thing
/// A page carries **either one understanding or one decision**, never both. The value pages
/// (02–04) put the real notch UI on screen instead of describing it, `connect` discloses what
/// installing does and does not touch, and only then does `consent` ask. Keeping the explanation
/// off the consent page is the basic courtesy of a screen that asks for access to a user's
/// configuration: nobody should be reading and deciding in the same breath.
///
/// # No skip
/// Agent Notch receives nothing without hooks, so a "later" option would only produce an app that
/// silently does nothing. The exits are an authorized install or quitting — and quitting after the
/// disclosure lands on `blocked` next launch, which states the app is stopped and offers exactly
/// one way back.
struct OnboardingView: View {
    let hookInstallation: HookInstallationCoordinator
    let onComplete: () -> Void

    /// The window this view is laid out in. Also used by `OnboardingWindowController`.
    ///
    /// One size for every page, so nothing resizes underfoot as the flow advances. The height is
    /// set by the tallest page — the live question sample, whose card grows to fit an option list
    /// beside its preview pane.
    static let windowSize = CGSize(width: 620, height: 520)

    @State private var step: OnboardingStep
    @State private var installation: Installation = .idle
    /// Where the consent page's Back returns to — the tour, or the stopped screen.
    @State private var consentReturn: OnboardingStep = .connect

    /// Progress feedback stays visible for at least this long per stage.
    ///
    /// Writing the hook files is local, synchronous, and takes a few milliseconds, so without a
    /// floor the disclosure of *what* is being written would flash past unread — the same reason
    /// `PermissionBanner` holds its decision feedback.
    private let minimumStageDuration: Duration = .milliseconds(420)

    private enum Installation: Equatable {
        case idle
        /// Writing the agent configuration files.
        case writing
        /// Re-reading them to confirm every event actually points at this runtime.
        case verifying
        case failed(String)

        var isRunning: Bool { self == .writing || self == .verifying }
    }

    init(
        hookInstallation: HookInstallationCoordinator,
        initialStep: OnboardingStep = .welcome,
        onComplete: @escaping () -> Void
    ) {
        self.hookInstallation = hookInstallation
        self.onComplete = onComplete
        self._step = State(initialValue: initialStep)
    }

    var body: some View {
        screen
            .id(step)
            // A crossfade rather than a slide: the flow branches (consent → installing → ready,
            // or back to consent on failure), and a directional slide would imply a single line
            // the user is being moved along.
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.22), value: step)
            // Fills the window rather than pinning a height: with `fullSizeContentView` the frame
            // is the content rect plus the titlebar, and a fixed height would leave a dead band
            // under the footer rail.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            // The window is `fullSizeContentView` with a transparent titlebar, and SwiftUI would
            // otherwise inset the content by the titlebar's height — leaving a dead band above the
            // page and cutting the background off at a hard edge.
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .environment(\.locale, AppLocalization.language.locale)
    }

    @ViewBuilder
    private var screen: some View {
        switch step {
        case .welcome: welcomeScreen
        case .sessions: sessionsScreen
        case .permissions: permissionsScreen
        case .questions: questionsScreen
        case .usage: usageScreen
        case .connect: connectScreen
        case .consent: consentScreen
        case .installing: installingScreen
        case .ready: readyScreen
        case .blocked: blockedScreen
        }
    }

    /// The system window background, edge to edge.
    ///
    /// This replaced a flat near-black fill with a 260pt accent gradient laid over its top: the
    /// gradient's frame ended mid-page, leaving a visible seam across the window and a green cast
    /// above it.
    ///
    /// It is deliberately **not** a translucent material. Under Liquid Glass, glass is for
    /// controls and floating surfaces that sit *above* content — a window's own canvas stays
    /// opaque, or the page's color becomes whatever happens to be behind the window, which is the
    /// same complaint in a new form. The glass here is on the buttons, where the system puts it.
    private var background: some View {
        Rectangle().fill(.windowBackground)
    }

    // MARK: - 01 Welcome

    private var welcomeScreen: some View {
        OnboardingScreen {
            productMark

            OnboardingHeading(
                title: L("Welcome to Agent Notch"),
                detail: L("Keep your coding agents in sight without leaving your work."),
                isHero: true
            )
        } footer: {
            ticks
            Spacer(minLength: 0)
            primaryButton(L("Continue")) { step = .sessions }
        }
    }

    private var productMark: some View {
        GlyphView(
            bitmap: GlyphBitmap.square(ProductMark.size, on: DSColors.ink) { x, y in
                ProductMark.outlineCells.contains(ProductMark.GridCell(col: x, row: y))
                    || ProductMark.pupilCells.contains(ProductMark.GridCell(col: x, row: y))
            },
            dot: 4,
            gap: 2
        )
        .accessibilityHidden(true)
    }

    // MARK: - 02 Sessions

    private var sessionsScreen: some View {
        OnboardingScreen {
            OnboardingHeading(
                eyebrow: "02 / SESSION",
                title: L("Live session state"),
                detail: L("See thinking, tool use, subagents, and completion at a glance.")
            )

            VStack(alignment: .leading, spacing: DSSpacing.md) {
                // The whole vocabulary, not a sample of it: each glyph is learned here against
                // its name, so the notch never needs a legend later. Three of eight would leave
                // the other five to be guessed at the moment they first appear.
                //
                // They are the animated `StateGlyphView`, not stills — the motion is part of how
                // each state is told apart, and `GlyphLegend` is the same list Settings shows.
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), alignment: .leading),
                        count: 2
                    ),
                    alignment: .leading,
                    spacing: DSSpacing.md
                ) {
                    ForEach(GlyphLegend.all) { entry in
                        glyphLegend(entry.state, label: entry.title)
                    }
                }

                OnboardingNotchPreview(state: .thinking, counter: (running: 3, total: 7))
            }
        } footer: {
            ticks
            Spacer(minLength: 0)
            backButton { step = .welcome }
            primaryButton(L("Next")) { step = .permissions }
        }
    }

    private func glyphLegend(_ state: Glyph.State, label: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            StateGlyphView(state: state, size: 22)
                .frame(width: 22, height: 22)
            Text(verbatim: label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    // MARK: - 03 Permissions

    private var permissionsScreen: some View {
        OnboardingScreen {
            OnboardingHeading(
                eyebrow: "03 / PERMISSION",
                title: L("Permission requests"),
                detail: L("Approve or deny agent actions directly from the notch.")
            )

            // The real banner, with a sample request. Rebuilding a lookalike here would let the
            // tour promise something the panel does not actually show.
            PermissionBanner(
                permission: Self.samplePermission,
                keyboardInteraction: sampleKeyboardInteraction,
                onApprove: {},
                onDeny: {}
            )
            .allowsHitTesting(false)
            .accessibilityLabel(L("Example of a permission request"))
        } footer: {
            ticks
            Spacer(minLength: 0)
            backButton { step = .sessions }
            primaryButton(L("Next")) { step = .questions }
        }
    }

    /// A sample request for the tour. `canRespond` is true so the banner shows its decision
    /// buttons; hit testing is off, so nothing here can be answered.
    private static let samplePermission = PermissionRequest(
        id: "onboarding-sample",
        agentType: .claudeCode,
        sessionId: "onboarding-sample",
        toolName: "Bash",
        toolInput: ["command": "rm -rf .next/cache"],
        toolUseId: "onboarding-sample",
        timestamp: .distantPast,
        canRespond: true
    )

    /// An unattached controller: it publishes no commands, so the sample banner cannot be
    /// triggered by a key press meant for the real panel.
    @State private var sampleKeyboardInteraction = KeyboardInteractionController()

    // MARK: - 04 Questions

    private var questionsScreen: some View {
        OnboardingScreen {
            OnboardingHeading(
                eyebrow: "04 / QUESTION",
                title: L("Answer questions in the notch"),
                detail: L("When the agent asks which way to go, pick an option and it continues.")
            )

            // The real banner again, and this one is **live**: the questions can actually be
            // answered. A question is not a permission — options rather than allow/deny, asked
            // one at a time — and reading that from a still image is not the same as pressing an
            // option and watching the second question slide in. Approvals stay untouchable
            // because a sample Approve has no meaning; picking an option has one.
            QuestionBanner(
                questions: Self.sampleQuestions,
                keyboardInteraction: sampleKeyboardInteraction,
                onAnswer: { _ in
                    // Nothing to send — no agent is connected yet — so the sample re-arms itself
                    // and can be walked through again. Changing the id resets the banner's own
                    // selection state.
                    sampleQuestionRound += 1
                }
            )
            .id(sampleQuestionRound)
            // The card's natural height changes between the two questions (one has a preview pane
            // beside its options, the other does not). The page centers its content, so that
            // difference would slide the heading up and down as the questions advance. Reserving
            // the taller of the two pins the heading in place and keeps the top and bottom margins
            // the same as every other page's.
            .frame(height: Self.questionSampleHeight, alignment: .top)
            .accessibilityLabel(L("Example of a question from the agent"))

            Text(l10n: "Try it: this sample is not sent anywhere.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } footer: {
            ticks
            Spacer(minLength: 0)
            backButton { step = .permissions }
            primaryButton(L("Next")) { step = .usage }
        }
    }

    /// Resets the sample question set once it has been answered through.
    @State private var sampleQuestionRound = 0

    /// Reserved height for the sample card, measured from the taller of the two questions (the
    /// one whose preview pane sets a 120pt floor) plus a few points of slack. Sized to the samples
    /// rather than to the tallest a real question could be: they are deliberately short, so this
    /// page's margins match the pages either side of it.
    private static let questionSampleHeight: CGFloat = 256

    /// Two sample questions, so the tab-style flow is visible: answering the first moves to the
    /// second, and the chevron in the header goes back. The first is single-select and carries
    /// previews (the side-by-side comparison pane), the second is multi-select — between them they
    /// cover every shape a real `AskUserQuestion` takes.
    ///
    /// `expiresAt` is left at its default, so no countdown is shown: a deadline on a sample would
    /// be a promise it cannot keep.
    private static let sampleQuestions: [AskQuestionInfo.Question] = [
        AskQuestionInfo.Question(
            question: L("Which approach should I take?"),
            header: L("Approach"),
            multiSelect: false,
            options: [
                AskQuestionInfo.Option(
                    label: L("Extend the current API"),
                    description: L("Fewer moving parts."),
                    // Previews are code, not prose, so they are not localized. Four short lines:
                    // the pane sits beside the option list, and a taller preview would grow the
                    // card past the height this page reserves.
                    preview: """
                        GET /v1/items
                        {
                          "id": 1,
                        +  "tags": []
                        }
                        """
                ),
                AskQuestionInfo.Option(
                    label: L("Add a new endpoint"),
                    description: L("Clean, but clients must update."),
                    preview: """
                        GET /v1/items
                        GET /v2/items
                        {
                          "id": 1,
                        + "tags": []
                        }
                        """
                ),
            ]
        ),
        AskQuestionInfo.Question(
            question: L("Which checks should run?"),
            header: L("Checks"),
            multiSelect: true,
            options: [
                AskQuestionInfo.Option(label: L("Unit tests"), description: nil, preview: nil),
                AskQuestionInfo.Option(label: L("Type check"), description: nil, preview: nil),
                AskQuestionInfo.Option(label: L("Lint"), description: nil, preview: nil),
            ]
        ),
    ]

    // MARK: - 04 Usage

    private var usageScreen: some View {
        OnboardingScreen {
            OnboardingHeading(
                eyebrow: "05 / USAGE",
                title: L("Usage at a glance"),
                detail: L("Track Claude and Codex rate limits from one place.")
            )

            // Both providers side by side: "one place" is a claim about layout, so it is shown
            // as layout. The cards are the usage page's own section headline.
            HStack(spacing: DSSpacing.sm) {
                usageCard(agentType: .claudeCode, label: L("Session"), percent: 48)
                usageCard(agentType: .codex, label: L("Weekly"), percent: 91)
            }
        } footer: {
            ticks
            Spacer(minLength: 0)
            backButton { step = .questions }
            primaryButton(L("Next")) { step = .connect }
        }
    }

    /// One provider's gauge, built the same way as `UsagePageView.sectionHeadline`.
    private func usageCard(agentType: AgentType, label: String, percent: Double) -> some View {
        HStack(spacing: 13) {
            // Forced to a ring: the 5×7 glyph number sits immediately to its right, so a
            // numeric gauge would print the same value twice.
            UsageGauge(
                usedPercent: percent,
                agentType: agentType,
                size: 26,
                forcedStyle: .ring
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    AgentMark(agentType: agentType, size: 8, alignedWithFontSize: 8)
                    Text(verbatim: "\(agentType.displayName.uppercased()) · \(label.uppercased())")
                        .font(DSTypography.mono(8, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(alignment: .bottom, spacing: 4) {
                    GlyphView(
                        bitmap: Glyph.number(
                            String(Int(percent.rounded())),
                            color: usageColor(percent)
                        )
                    )
                    Text(verbatim: "%")
                        .font(DSTypography.mono(9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        // A glyph number's bottom edge is its baseline; text's is the
                        // descender, so plain .bottom would leave the % floating.
                        .alignmentGuide(.bottom) { $0[.firstTextBaseline] }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .panelCard(border: percent >= 90 ? DSColors.signalError.opacity(0.3) : DSColors.lineDefault)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agentType.displayName) \(label)")
        .accessibilityValue(L("\(Int(percent.rounded())) percent"))
    }

    /// The same thresholds the usage page uses, so a number that reads as a warning there reads
    /// as one here.
    private func usageColor(_ percent: Double) -> Color {
        switch percent {
        case 90...: DSColors.signalError
        case 70..<90: DSColors.signalAlert
        default: DSColors.ink.opacity(0.8)
        }
    }

    // MARK: - 05 Connect

    private var connectScreen: some View {
        OnboardingScreen {
            // No icon. The two disclosure blocks below are what this page is for, and a symbol
            // beside the headline would only be decoration competing with them.
            OnboardingHeading(
                eyebrow: "06 / CONNECT",
                title: L("Connect Claude Code and Codex"),
                detail: L("Agent Notch receives session updates through agent hooks.")
            )

            // Disclosed as a pair. "What it does" alone leaves the user to guess the blast
            // radius, and the honest answer — that unrelated hooks are left alone — is the
            // part that makes the decision on the next page a small one.
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                disclosureCard(
                    heading: L("What it does"),
                    body: L("Adds Agent Notch commands to the Claude Code and Codex hook settings.")
                )
                disclosureCard(
                    heading: L("What it does not do"),
                    body: L("Keeps your existing settings and unrelated hooks unchanged.")
                )
            }
            // Each card ends in a spacer so its text stays at the top and both cards match
            // height. That makes them vertically greedy, which would otherwise swallow the
            // page's free space and push the rest of the content out of the frame.
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                noteRow(L("You can check or reinstall the hooks later from Settings."))
                noteRow(L("Codex may ask you to trust the hook the first time it runs."))
            }
        } footer: {
            ticks
            Spacer(minLength: 0)
            backButton { step = .usage }
            // Deliberately not "Allow": this page has no decision on it.
            primaryButton(L("Next")) { goToConsent(from: .connect) }
        }
    }

    private func disclosureCard(heading: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(verbatim: heading.uppercased())
                .font(DSTypography.mono(9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            Text(verbatim: body)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        // A fill rather than another material: the window is already one, and Apple's guidance is
        // not to stack translucent surfaces. `.quinary` is the faintest step that still draws an
        // edge, which is all these two blocks need to read as a pair.
        .background(.quinary, in: DSShape.rounded(DSShape.cell))
        .accessibilityElement(children: .combine)
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Circle()
                .fill(.tertiary)
                .frame(width: 3, height: 3)
                .padding(.top, 6)
                .accessibilityHidden(true)

            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - 06 Consent

    private var consentScreen: some View {
        OnboardingScreen {
            OnboardingHeading(
                title: L("Agent Notch needs agent hooks"),
                detail: L(
                    "Without hooks, Agent Notch receives neither session state nor permission requests. They are installed only after you allow it below."
                )
            )

            // The exact write targets, read from the installer itself rather than restated, so
            // the disclosure cannot fall out of step with what is written.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.installationTargets, id: \.self) { path in
                    Text(verbatim: path)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, DSSpacing.md)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DSColors.signalAlert.opacity(0.5))
                    .frame(width: 2)
            }

            if case .failed(let message) = installation {
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(DSColors.signalError)
                .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            backButton { step = consentReturn }
            Spacer(minLength: 0)
            quitButton
            primaryButton(L("Allow and Install Hooks"), tint: DSColors.signalAlert) {
                installHooks()
            }
        }
    }

    /// Shown with the home directory abbreviated — the full path adds nothing but width.
    private static let installationTargets: [String] = HookInstaller.installationTargets()
        .map { ($0 as NSString).abbreviatingWithTildeInPath }

    // MARK: - 07 Installing

    private var installingScreen: some View {
        OnboardingScreen {
            OnboardingHeading(title: L("Installing hooks"))

            // The files go out in a single installer call, so they share one state rather than
            // ticking over individually — a per-file sequence here would be invented. The
            // verification row is a real second step: it re-reads the files and checks that
            // every event points at this runtime.
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                ForEach(Self.installationTargets, id: \.self) { path in
                    OnboardingProgressRow(
                        label: path,
                        state: installation == .writing ? .active : .done,
                        status: installation == .writing ? L("Writing…") : L("Added")
                    )
                }

                OnboardingProgressRow(
                    label: L("Checking the installed hooks"),
                    state: installation == .verifying ? .active : .waiting,
                    status: installation == .verifying ? L("Checking…") : nil
                )
            }

            stageBar
        } footer: {
            Spacer(minLength: 0)
            // Nothing to press: the install is not interruptible, and stopping halfway would
            // leave the agent configuration in a state nobody asked for.
            primaryButton(L("Next")) {}
                .disabled(true)
        }
    }

    /// One segment per real stage — write, then verify. A percentage bar would have to invent a
    /// number, since neither stage reports partial progress.
    private var stageBar: some View {
        HStack(spacing: 4) {
            Capsule(style: .continuous).fill(.primary)
            Capsule(style: .continuous).fill(.primary)
                .opacity(installation == .verifying ? 1 : 0.15)
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel(installation == .verifying ? L("Checking…") : L("Writing…"))
    }

    // MARK: - 08 Ready

    private var readyScreen: some View {
        OnboardingScreen {
            StateGlyphView(state: .complete, size: 44)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            OnboardingHeading(
                title: L("Connected"),
                detail: L("The next time you start claude or codex, the notch shows its state.")
            )

            OnboardingNotchPreview(state: .standby)
        } footer: {
            openHint
            Spacer(minLength: 0)
            primaryButton(L("Get Started")) { onComplete() }
        }
    }

    /// The real, user-configurable shortcut — read from the same store the hot key uses, so the
    /// hint cannot advertise a chord that is no longer bound.
    @ViewBuilder
    private var openHint: some View {
        if let chord = KeyboardShortcuts.getShortcut(for: .jumpToNotification)
            .flatMap({ ShortcutChord.fromDisplayDescription($0.description) })
        {
            HStack(spacing: DSSpacing.sm) {
                KeyHint(chord: chord)
                Text(l10n: "opens the notch anytime")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Declined

    private var blockedScreen: some View {
        OnboardingScreen {
            StateGlyphView(state: .fault, size: 38)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

            OnboardingHeading(
                title: L("Stopped because hooks are not installed"),
                detail: L(
                    "Agent Notch is receiving nothing from your agents. Installing the hooks resumes it from here."
                )
            )
        } footer: {
            quitButton
            Spacer(minLength: 0)
            // One way back, and it goes through the consent page rather than installing
            // straight from here — the decision keeps its disclosure.
            primaryButton(L("Install Hooks"), tint: DSColors.signalAlert) {
                goToConsent(from: .blocked)
            }
        }
    }

    // MARK: - Footer controls

    @ViewBuilder
    private var ticks: some View {
        if let index = step.tourIndex {
            OnboardingProgressTicks(current: index, total: OnboardingStep.tour.count)
        }
    }

    /// The page's one forward action. `.glassProminent` is the system's Liquid Glass primary, so
    /// it picks up the same lensing and press behavior as the rest of macOS 26 instead of a
    /// hand-tinted pill. `tint` is passed only where the action carries a warning (installing
    /// hooks), which is the one case the color says something the label cannot.
    private func primaryButton(
        _ title: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(tint)
        .keyboardShortcut(.defaultAction)
    }

    /// Going back is a peer of going forward, so it takes the plain glass style: same shape and
    /// size, no fill. Hierarchy comes from the fill alone.
    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(l10n: "Back")
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    /// Quitting is neither the forward action nor its peer — it is the way out of the flow, and it
    /// should not compete for the eye. Plain text, at the same size as the other labels.
    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text(l10n: "Quit Agent Notch")
        }
        .buttonStyle(.plain)
        .font(.body)
        .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    /// Entering consent means the disclosure has been read. Recording it here is what lets a
    /// relaunch skip straight to `blocked` instead of replaying the tour at someone who has
    /// already seen it and said no.
    ///
    /// Back has to return where the user came from: reached from `blocked`, it would otherwise
    /// drop them into the middle of a tour they never asked to see again.
    private func goToConsent(from origin: OnboardingStep) {
        Defaults[.hasReviewedHookConsent] = true
        consentReturn = origin
        step = .consent
    }

    private func installHooks() {
        guard !installation.isRunning else { return }
        installation = .writing
        step = .installing

        Task { @MainActor in
            try? await Task.sleep(for: minimumStageDuration)

            switch hookInstallation.installWithUserConsent() {
            case .installed:
                installation = .verifying
                try? await Task.sleep(for: minimumStageDuration)
                // Reading the files back means the success screen reports what is on disk,
                // not what we believe we wrote.
                guard hookInstallation.status() == .installed else {
                    fail(L("The hooks were written but could not be verified. Try installing again."))
                    return
                }
                installation = .idle
                step = .ready

            case .developmentCLIUnavailable:
                fail(L("The hook helper could not be found. Reinstall Agent Notch and try again."))

            case .failed(let message):
                fail(L("Hook installation failed: \(message)"))
            }
        }
    }

    /// Failures go back to the consent page, where the message sits next to the button that
    /// retries it. Leaving it on the progress page would show progress that has stopped.
    private func fail(_ message: String) {
        installation = .failed(message)
        step = .consent
    }
}

#Preview("Onboarding") {
    OnboardingView(hookInstallation: .shared, onComplete: {})
}
