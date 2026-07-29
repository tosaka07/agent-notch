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

        try appendMessage(index: 60, paragraphs: 10, to: transcriptURL)
        manager.notifyChange()
        try await settle(hostingView: hostingView, window: window)

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

        try appendMessage(index: 61, paragraphs: 15, to: transcriptURL)
        manager.notifyChange()
        try await settle(hostingView: hostingView, window: window)

        let distanceWhileReadingHistory = scrollView.documentVisibleRect.minY
        #expect(
            distanceWhileReadingHistory > 40,
            "A new row pulled the user out of history and back to newest"
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
        window: NSWindow
    ) async throws -> NSScrollView {
        for _ in 0..<40 {
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

    private func settle<Content: View>(
        hostingView: NSHostingView<Content>,
        window: NSWindow
    ) async throws {
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
    }

    private enum TimelineTestError: Error {
        case timelineDidNotLoad
    }
}
