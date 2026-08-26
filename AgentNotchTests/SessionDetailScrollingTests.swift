import AgentNotchCore
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentNotch

@Suite("Session detail scrolling")
@MainActor
struct SessionDetailScrollingTests {
    @Test("A lazy inverted transcript opens at its newest row")
    func invertedTimelineOpensAtNewest() async throws {
        let transcriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-inverted-\(UUID()).jsonl")
        try makeTranscript(lineCount: 60).write(to: transcriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: transcriptURL) }

        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "inverted", agentType: .claudeCode)
        session.cwd = "/tmp/inverted"
        session.status = .idle
        session.transcriptPath = transcriptURL.path
        session.tasks = [
            AgentTask(id: "task", subject: "Verify the detached chat viewport", status: .inProgress)
        ]

        let hostingView = NSHostingView(
            rootView: SessionDetailView(
                session: session,
                sessionManager: manager,
                physicalNotchHeight: 32,
                onBack: {},
                onClose: {},
                keyboardInteraction: KeyboardInteractionController()
            )
            .frame(width: 620, height: 500)
            .environment(\.colorScheme, .dark)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView

        let scrollView = try await waitForScrollableTimeline(in: hostingView, window: window)
        let distanceFromNewest = scrollView.documentVisibleRect.minY

        #expect(
            abs(distanceFromNewest) <= 8.5,
            "The inverted timeline opened \(distanceFromNewest)pt away from its logical origin"
        )

        let heightBeforeFollowingAppend = scrollView.documentView?.bounds.height ?? 0
        try appendMessage(index: 60, paragraphs: 10, to: transcriptURL)
        manager.notifyChange()
        try await settle(
            hostingView: hostingView,
            window: window,
            scrollView: scrollView,
            heightBefore: heightBeforeFollowingAppend
        )

        let distanceAfterAppend = scrollView.documentVisibleRect.minY
        #expect(
            abs(distanceAfterAppend) <= 8.5,
            "A timeline already at newest stopped following by \(distanceAfterAppend)pt"
        )

        try await scrollIntoHistory(in: scrollView, distance: 240)

        let distanceAfterUserScroll = scrollView.documentVisibleRect.minY
        #expect(
            distanceAfterUserScroll > 40,
            "The scroll view did not move the timeline into history"
        )

        let heightBeforeHistoryAppend = scrollView.documentView?.bounds.height ?? 0
        try appendMessage(index: 61, paragraphs: 15, to: transcriptURL)
        manager.notifyChange()
        try await settle(
            hostingView: hostingView,
            window: window,
            scrollView: scrollView,
            heightBefore: heightBeforeHistoryAppend
        )

        let distanceWhileReadingHistory = scrollView.documentVisibleRect.minY
        #expect(
            distanceWhileReadingHistory > 40,
            "A new row pulled the user out of history and back to newest"
        )
    }

    @Test("A message written while the selected session is loading still appears")
    func messageArrivingDuringReadAppears() async throws {
        let transcriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-notch-in-flight-\(UUID()).jsonl")
        let filler =
            #"{"type":"attachment","payload":"\#(String(repeating: "x", count: 320))"}"# + "\n"
        try String(repeating: filler, count: 60_000)
            .write(to: transcriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: transcriptURL) }

        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "in-flight", agentType: .claudeCode)
        session.cwd = "/tmp/in-flight"
        session.status = .permissionWaiting
        session.transcriptPath = transcriptURL.path

        let hostingView = NSHostingView(
            rootView: SessionDetailView(
                session: session,
                sessionManager: manager,
                physicalNotchHeight: 32,
                onBack: {},
                onClose: {},
                keyboardInteraction: KeyboardInteractionController()
            )
            .frame(width: 620, height: 500)
            .environment(\.colorScheme, .dark)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        // This fixture keeps the initial read in flight long enough to append the context message
        // at the same boundary where an AskUserQuestion notification reaches the open detail view.
        try await Task.sleep(for: .milliseconds(100))
        try appendMessage(index: 1, paragraphs: 80, to: transcriptURL)
        manager.notifyChange()

        _ = try await waitForScrollableTimeline(
            in: hostingView,
            window: window,
            attempts: 160
        )
    }

    private func scrollIntoHistory(
        in scrollView: NSScrollView,
        distance: CGFloat
    ) async throws {
        for _ in 0..<10 {
            let clipView = scrollView.contentView
            var origin = clipView.bounds.origin
            origin.y += distance
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)

            try await Task.sleep(for: .milliseconds(25))
            if scrollView.documentVisibleRect.minY > 40 { return }
        }
    }

    private func waitForScrollableTimeline(
        in hostingView: NSHostingView<some View>,
        window: NSWindow,
        attempts: Int = 40
    ) async throws -> NSScrollView {
        for _ in 0..<attempts {
            window.layoutIfNeeded()
            hostingView.layoutSubtreeIfNeeded()

            if let scrollView = descendants(of: hostingView)
                .compactMap({ $0 as? NSScrollView })
                .filter({
                    guard let documentView = $0.documentView else { return false }
                    return documentView.bounds.height > $0.documentVisibleRect.height + 20
                })
                .max(by: {
                    ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0)
                })
            {
                return scrollView
            }

            try await Task.sleep(for: .milliseconds(25))
        }

        Issue.record("The asynchronously loaded timeline never became scrollable")
        throw TimelineTestError.timelineDidNotLoad
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func makeTranscript(lineCount: Int) -> String {
        (0..<lineCount).map { index in
            message(index: index, paragraphs: 5)
        }
        .joined(separator: "\n")
    }

    private func appendMessage(index: Int, paragraphs: Int, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + message(index: index, paragraphs: paragraphs)).utf8))
    }

    private func message(index: Int, paragraphs: Int) -> String {
        let role = index.isMultiple(of: 2) ? "user" : "assistant"
        let body = (0..<paragraphs)
            .map { paragraph in
                "Message \(index), paragraph \(paragraph): variable-height rich text for scrolling."
            }
            .joined(separator: "\n\n")
        let payload: [String: Any] = [
            "type": role,
            "message": [
                "role": role,
                "content": body,
            ],
            "timestamp": String(
                format: "2026-07-28T11:%02d:%02d.000Z",
                index / 60,
                index % 60
            ),
            "uuid": "message-\(index)",
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Waits for an appended message to land and the timeline to stop moving.
    ///
    /// A fixed sleep is not enough. Reloading the transcript rebuilds the
    /// document view, which drops the scroll offset to zero before the intended
    /// position is restored, so a slower machine can read that intermediate
    /// state instead of the settled one. Waiting for the document to grow proves
    /// the reload arrived; waiting for the offset to hold still proves the
    /// restore finished. A timeline that genuinely ends up back at newest also
    /// settles — at zero — so a real regression still fails the assertion.
    private func settle<Content: View>(
        hostingView: NSHostingView<Content>,
        window: NSWindow,
        scrollView: NSScrollView,
        heightBefore: CGFloat,
        attempts: Int = 80
    ) async throws {
        for _ in 0..<attempts {
            window.layoutIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            if (scrollView.documentView?.bounds.height ?? 0) > heightBefore { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        // Three matching samples, rather than two: the offset can pause for a
        // single frame between the reset and the restore.
        var previous: CGFloat?
        var stableSamples = 0
        for _ in 0..<attempts {
            window.layoutIfNeeded()
            hostingView.layoutSubtreeIfNeeded()

            let offset = scrollView.documentVisibleRect.minY
            if let previous, abs(offset - previous) < 0.5 {
                stableSamples += 1
                if stableSamples >= 3 { return }
            } else {
                stableSamples = 0
            }
            previous = offset

            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private enum TimelineTestError: Error {
        case timelineDidNotLoad
    }
}
