import AgentNotchCore
import AppKit
import SwiftUI
import Testing

@testable import AgentNotch

@Suite("Permission banner pointer interaction", .serialized)
@MainActor
struct PermissionBannerPointerTests {
    @Test("Approve accepts a pointer click after the safety delay")
    func approveAcceptsPointerClick() async throws {
        let recorder = PermissionPointerRecorder()
        let rootView =
            PermissionBanner(
                permission: PermissionRequest(
                    id: "permission",
                    agentType: .claudeCode,
                    sessionId: "session",
                    toolName: "Bash",
                    toolInput: ["command": "echo test"],
                    toolUseId: "tool",
                    timestamp: .now,
                    canRespond: true
                ),
                keyboardInteraction: KeyboardInteractionController(),
                onApprove: { recorder.approvals += 1 },
                onDeny: {}
            )
            .padding(20)
            .frame(width: 620, height: 300, alignment: .bottom)
            .environment(\.colorScheme, .dark)

        let hostingView = NotchHostingView(rootView: rootView)
        let window = NotchPanel(
            contentRect: NSRect(x: 100, y: 100, width: 620, height: 300)
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        // The modifier and submission callback each start a main-actor task.
        // Keep retrying across the full CI scheduling window rather than
        // assuming both tasks run during the first half-second of clicks.
        for _ in 0..<100 where recorder.approvals == 0 {
            try click(
                at: NSPoint(x: hostingView.bounds.maxX - 110, y: 48),
                in: window
            )
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(recorder.approvals == 1)
    }

    private func click(at point: NSPoint, in window: NSWindow) throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        for (index, eventType) in [
            NSEvent.EventType.leftMouseDown,
            .leftMouseUp,
        ].enumerated() {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: eventType,
                    location: point,
                    modifierFlags: [],
                    timestamp: timestamp + Double(index) * 0.01,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: index,
                    clickCount: 1,
                    pressure: eventType == .leftMouseDown ? 1 : 0
                )
            )
            window.sendEvent(event)
        }
    }
}

@MainActor
private final class PermissionPointerRecorder {
    var approvals = 0
}
