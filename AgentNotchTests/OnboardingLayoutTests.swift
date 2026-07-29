import AppKit
import SwiftUI
import Testing

@testable import AgentNotch

/// Every onboarding page has to fit the one window size the flow uses.
///
/// The window is a fixed size with no scroll view, so a page whose content outgrows it is silently
/// clipped — and the footer rail, which owns the only way forward, is what goes first.
///
/// # What this catches, and what it does not
/// It catches content that is **genuinely taller than the window**: a row added to a page, a
/// reserved height raised too far, a translation that wraps to another line. Verified to fail by
/// over-sizing a page and watching both expectations trip.
///
/// It does **not** catch a greedy sibling squeezing the others — the connect page's disclosure
/// cards once ended in a `Spacer`, took the page's slack, and pushed the eyebrow out of frame at
/// the top. SwiftUI reports the same ideal size either way and draws pages into a single layer, so
/// nothing here can see it. That class of bug is still only visible by looking.
@Suite("Onboarding layout")
@MainActor
struct OnboardingLayoutTests {
    @Test("Every page fits the window without clipping", arguments: OnboardingStep.allCases)
    func pageFitsTheWindow(step: OnboardingStep) {
        let hostingView = makeHostingView(step: step)

        // The page fills the window by design, so its own height says nothing. `fittingSize` is
        // the height the content actually needs.
        let needed = hostingView.fittingSize.height
        #expect(needed <= OnboardingView.windowSize.height)
    }

    @Test("Every page keeps its footer rail on screen", arguments: OnboardingStep.allCases)
    func footerStaysInsideTheWindow(step: OnboardingStep) {
        let hostingView = makeHostingView(step: step)

        // The rail is pinned to the bottom, so anything drawn below the window's bounds means the
        // body pushed it out. Half a point of tolerance for the hairline separator's rounding.
        let overflow =
            descendants(of: hostingView)
            .filter { !$0.frame.isEmpty }
            .map { $0.convert($0.bounds, to: hostingView).maxY }
            .max() ?? 0
        #expect(overflow <= OnboardingView.windowSize.height + 0.5)
    }

    // MARK: - Helpers

    /// A coordinator whose closures do nothing: mounting a page must never write to the real
    /// `~/.claude` or `~/.codex`.
    private func makeInertCoordinator() -> HookInstallationCoordinator {
        HookInstallationCoordinator(
            context: .init(
                distributionChannel: "production",
                appExecutableURL: nil,
                isExecutableFile: { _ in true }
            ),
            install: { _ in }
        )
    }

    private func makeHostingView(step: OnboardingStep) -> NSHostingView<OnboardingView> {
        let hostingView = NSHostingView(
            rootView: OnboardingView(
                hookInstallation: makeInertCoordinator(),
                initialStep: step,
                onComplete: {}
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: OnboardingView.windowSize)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
