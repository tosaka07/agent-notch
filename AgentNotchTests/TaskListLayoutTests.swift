import AgentNotchCore
import AppKit
import SwiftUI
import Testing

@testable import AgentNotch

@Suite("Task list layout")
@MainActor
struct TaskListLayoutTests {
    @Test("Expanded list keeps card gaps in the scroll responder region")
    func expandedListUsesAnEagerStack() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/Pages/ExpandedPageView.swift"),
            encoding: .utf8
        )
        let bodyStart = try #require(source.range(of: "var body: some View"))
        let bodyEnd = try #require(source.range(of: "/// Shown when there is no session at all."))
        let body = String(source[bodyStart.lowerBound..<bodyEnd.lowerBound])

        #expect(body.contains("\n                        VStack(spacing: Self.sessionCardSpacing)"))
        #expect(!body.contains("LazyVStack"))
    }

    @Test("A work context chip grows its own surface instead of opening a second one")
    func workContextChipGrowsInPlace() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/SessionDetail/SessionDetailView.swift"),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "// MARK: - Tasks / Subagents / Team"))
        let end = try #require(source.range(of: "// MARK: - Timeline"))
        let workContext = String(source[start.lowerBound..<end.lowerBound])

        // A chip is a control, not a card: no glass, no border, and the plain
        // pressable surface the header's other buttons use.
        #expect(!workContext.contains("glassEffect"))
        #expect(!workContext.contains("notchCard"))
        #expect(!workContext.contains(".stroke("))
        #expect(workContext.components(separatedBy: "DSSurfaceFill(.control)").count == 2)

        let chipStart = try #require(
            workContext.range(of: "private func workContextChip(")
        )
        let chipEnd = try #require(
            workContext.range(of: "private func expandedWorkContextList(")
        )
        let chip = String(workContext[chipStart.lowerBound..<chipEnd.lowerBound])

        // The list lives in the same cell as the header button, so opening one
        // grows that surface rather than adding a second one below it.
        #expect(
            chip.contains(
                """
                            if isExpanded {
                                expandedWorkContextList(kind)
                """
            )
        )
        // Padding and alignment are stated once, outside any conditional, so
        // the label the pointer just pressed does not move as the cell grows.
        #expect(
            chip.contains(
                """
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                """
            )
        )
        // Two open sections would split the row's width into narrow columns.
        #expect(chip.contains("expandedWorkContext = isExpanded ? nil : kind"))
        // Toggling must not clear a measurement. onGeometryChange only reports
        // changes, so a chip reopened at the size it already had never reports
        // again and would stay at the cleared height.
        #expect(!workContext.contains("workContextHeights = [:]"))
        #expect(!workContext.contains("workContextHeights[kind] = 0"))
        #expect(workContext.contains("workContextHeights[kind] ?? 0"))
    }

    @Test("Detail header and chat occupy separate regions")
    func workContextOverlaysTheLog() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/SessionDetail/SessionDetailView.swift"),
            encoding: .utf8
        )
        let bodyStart = try #require(source.range(of: "    var body: some View {"))
        let bodyEnd = try #require(source.range(of: "    // MARK: - Notch top bar"))
        let body = String(source[bodyStart.lowerBound..<bodyEnd.lowerBound])

        // The header is a sibling above the timeline, so chat rows cannot pass
        // underneath it.
        #expect(body.contains("\n            detailHeader\n"))
        #expect(!source.contains(".safeAreaBar(edge: .top, spacing: 0)"))
        #expect(source.contains(".safeAreaBar(edge: .bottom, spacing: 0)"))
        let timelineStart = try #require(
            source.range(of: "    private var timelineContent: some View {")
        )
        let timelineEnd = try #require(
            source.range(of: "    private var invertedTimeline: some View {")
        )
        let timelineSurface = String(source[timelineStart.lowerBound..<timelineEnd.lowerBound])
        #expect(timelineSurface.contains("interruptionBar"))
        #expect(!timelineSurface.contains("InvertedTimelineRow"))
        #expect(timelineSurface.contains(".overlay(alignment: .topLeading)"))
        #expect(timelineSurface.contains("collapsibleSections"))
        #expect(!timelineSurface.contains(".scrollEdgeEffectStyle"))

        let headerBarStart = try #require(
            source.range(of: "    private var detailHeader: some View {")
        )
        let headerBarEnd = try #require(
            source.range(of: "    /// The header.", range: headerBarStart.upperBound..<source.endIndex)
        )
        let headerBar = String(source[headerBarStart.lowerBound..<headerBarEnd.lowerBound])
        #expect(headerBar.contains("header"))
        #expect(!headerBar.contains("collapsibleSections"))
        #expect(!headerBar.contains("Material"))
        #expect(!headerBar.contains(".glassEffect("))
        #expect(headerBar.contains(".frame(height: 1 / max(displayScale, 1))"))

        // The panel is still springing open while the page is already laid out
        // at its final size, so anything the page centers sits off the glass's
        // centre until the two agree. Most transcripts load inside that window,
        // so the screen waits it out rather than flashing a misplaced spinner.
        #expect(timelineSurface.contains("timeline.isEmpty && isLoading && showsSpinner"))
        #expect(source.contains("spinnerDelay: TimeInterval = 0.45"))
    }

    @Test("Detail glass controls use one container without matched geometry identities")
    func detailGlassControlsAvoidMatchedGeometry() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/SessionDetail/SessionDetailView.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("GlassEffectContainer(spacing: 0)"))
        #expect(!source.contains("DetailGlassID"))
        #expect(!source.contains("detailGlassNamespace"))
        #expect(source.contains(".glassEffectTransition(.identity)"))
    }

    @Test("Where the log opens is decided by layout, not by timing")
    func timelineOpensAtTheNewestDeterministically() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/SessionDetail/SessionDetailView.swift"),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "    private var invertedTimeline: some View {"))
        let end = try #require(
            source.range(of: "    // MARK: - Navigation", range: start.upperBound..<source.endIndex)
        )
        let timeline = String(source[start.lowerBound..<end.lowerBound])

        // Newest sits at the logical origin. Only the viewport and rows are
        // transformed; fixed header and response controls remain outside this
        // section in ordinary coordinates.
        #expect(source.contains("@State private var scrollPosition = ScrollPosition()"))
        #expect(timeline.contains("TimelineRow.rows(from: timeline).reversed()"))
        #expect(timeline.contains(".modifier(InvertedTimelineRow())"))
        #expect(timeline.contains(".scaleEffect(x: 1, y: -1"))
        #expect(timeline.contains("LazyVStack"))
        #expect(!timeline.contains(".scrollTargetLayout()"))
        #expect(!timeline.contains(".defaultScrollAnchor"))
        #expect(timeline.contains(".scrollPosition($scrollPosition)"))
        #expect(timeline.contains(".scrollIndicators(.hidden)"))
        #expect(!source.contains("ScrollViewProxy"))
        #expect(source.contains("scrollPosition.scrollTo(edge: .top)"))
        #expect(!source.contains("scrollPosition.scrollTo(edge: .bottom)"))
        #expect(!timeline.contains("safeAreaInset"))
        #expect(!timeline.contains("interruptionBar"))
        #expect(!timeline.contains("collapsibleSections"))
    }

    @Test("One transcript read at a time, with the fingerprint claimed up front")
    func transcriptReadsDoNotOverlap() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/SessionDetail/SessionDetailView.swift"),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "    private func loadTimelineAsync() {"))
        let end = try #require(
            source.range(of: "/// The loading ring.", range: start.upperBound..<source.endIndex)
        )
        let load = String(source[start.lowerBound..<end.lowerBound])

        // Reads take 41ms to 1210ms depending on transcript size. Claiming the
        // fingerprint only after the read let every notification arriving in
        // that window start another parse of the same bytes, each finishing
        // into another full rebuild of the log.
        let claim = try #require(load.range(of: "loadedSignature = signature"))
        let read = try #require(load.range(of: "Task.detached"))
        #expect(claim.lowerBound < read.lowerBound)
        #expect(load.contains("guard !isReadingTranscript else { return }"))
    }

    @Test("Overview retains one host while heavy pages still swap immediately")
    func overviewIdentityHostIsScoped() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootSource = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/Root/NotchRootView.swift"),
            encoding: .utf8
        )
        let overviewSource = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/Root/NotchOverviewView.swift"),
            encoding: .utf8
        )

        // Overview owns a lightweight retained identity host. Detail and usage
        // remain outside it so an outgoing ScrollView is never retained merely
        // to animate a page transition.
        #expect(
            rootSource.contains("if NotchOverviewTarget(mode: viewModel.mode) != nil")
        )
        #expect(rootSource.contains("NotchOverviewView("))
        #expect(
            rootSource.contains(
                ".transaction(value: viewModel.mode) { $0.animation = nil }"
            )
        )
        #expect(!rootSource.contains(".transition("))

        // A fresh transaction animates the retained overview after the mode
        // transaction. Whole-page identity tricks previously duplicated views.
        #expect(overviewSource.contains("CompactPageView("))
        #expect(overviewSource.contains(".task(id: target)"))
        #expect(!overviewSource.contains(".matchedGeometryEffect("))
        #expect(!overviewSource.contains(".id("))
    }

    @Test("Card scrim follows the rounded glass shape")
    func cardScrimIsRounded() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf:
                repository
                .appendingPathComponent("AgentNotch/UI/DesignSystem/Modifiers/NotchCard.swift"),
            encoding: .utf8
        )

        #expect(source.contains(".fill(DSColors.canvas.opacity(scrimOpacity))"))
        #expect(!source.contains("sized.background(DSColors.canvas.opacity(scrimOpacity))"))
    }

    @Test("Task glyph is vertically centered with a single-line subject")
    func glyphIsCenteredWithSubject() throws {
        let hostingView = NSHostingView(
            rootView:
                TaskListSection(
                    tasks: [
                        AgentTask(id: "1", subject: "MMMM", status: .pending)
                    ]
                )
                .frame(width: 180, height: 32, alignment: .leading)
                .padding(4)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 188, height: 40)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let scale = CGFloat(bitmap.pixelsWide) / hostingView.bounds.width
        let glyphBounds = try #require(visibleBounds(in: bitmap, xRange: 4..<19))
        let textBounds = try #require(visibleBounds(in: bitmap, xRange: 25..<80))
        let centerDelta = abs(glyphBounds.midY - textBounds.midY) / scale

        #expect(
            centerDelta <= 1.5,
            "Glyph and subject centers differ by \(centerDelta) pt"
        )
    }

    private func visibleBounds(
        in bitmap: NSBitmapImageRep,
        xRange: Range<CGFloat>
    ) -> CGRect? {
        var bounds = CGRect.null
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let pixelRange = Int(xRange.lowerBound * scale)..<Int(xRange.upperBound * scale)

        for y in 0..<bitmap.pixelsHigh {
            for x in pixelRange where x < bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.deviceRGB)
                else { continue }

                if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.08 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }

        return bounds.isNull ? nil : bounds
    }
}
