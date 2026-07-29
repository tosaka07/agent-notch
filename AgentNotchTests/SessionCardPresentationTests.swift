import AppKit
import SwiftUI
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Session card presentation")
struct SessionCardPresentationTests {
    @Test("A restored done session keeps its title and completion summary")
    func restoredDoneSessionShowsCompletionSummary() {
        let source = UnifiedSession(id: "done-session", agentType: .codex)
        source.status = .done
        source.sessionTitle = "Persist session cards"
        source.firstUserPrompt = "Implement session persistence"
        source.lastUserPrompt = "Continue with the final checks"
        source.lastAssistantMessage = "Snapshots now preserve card content"
        let restored = SessionSnapshot(session: source).makeRestoredSession()

        let presentation = SessionCardPresentation.content(
            session: restored,
            promptSource: .lastUserMessage
        )

        #expect(presentation.titleText == "Persist session cards")
        #expect(presentation.activityText == "Snapshots now preserve card content")
        #expect(presentation.metadataText == "\(L("Last seen")) · \(L("Done"))")
    }

    @Test("The selected prompt is only a title fallback")
    func promptSelectionIsATitleFallback() {
        let source = UnifiedSession(id: "prompt-fallback", agentType: .codex)
        source.status = .done
        source.firstUserPrompt = "Implement session persistence"
        source.lastUserPrompt = "Continue with the final checks"
        let restored = SessionSnapshot(session: source).makeRestoredSession()

        let first = SessionCardPresentation.content(
            session: restored,
            promptSource: .firstUserMessage
        )
        let latest = SessionCardPresentation.content(
            session: restored,
            promptSource: .lastUserMessage
        )

        #expect(first.titleText == "Implement session persistence")
        #expect(latest.titleText == "Continue with the final checks")
        #expect(latest.activityText == "\(L("Last seen")) · \(L("Done"))")
    }

    @Test("A per-session preference can replace a stale title with the latest prompt")
    func latestPromptPreferenceOverridesSessionTitle() {
        let session = UnifiedSession(id: "title-preference", agentType: .codex)
        session.sessionTitle = "Original implementation task"
        session.firstUserPrompt = "Implement the original task"
        session.lastUserPrompt = "Now review the release notes"

        let title = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage,
            titleDisplayPreference: .sessionTitle
        )
        let latestPrompt = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage,
            titleDisplayPreference: .latestPrompt
        )

        #expect(title.titleText == "Original implementation task")
        #expect(latestPrompt.titleText == "Now review the release notes")
    }

    @Test("An arriving title becomes primary unless the latest prompt was explicitly selected")
    func arrivingTitleRespectsExplicitPromptPreference() {
        let session = UnifiedSession(id: "arriving-title", agentType: .codex)
        session.firstUserPrompt = "Review the original implementation"
        session.lastUserPrompt = "Now prepare the release notes"

        let beforeTitle = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage
        )
        #expect(beforeTitle.titleText == "Review the original implementation")
        #expect(!SessionCardPresentation.hasSessionTitle(session))

        session.sessionTitle = "Original implementation work"

        let automatic = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage
        )
        let explicitPrompt = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage,
            titleDisplayPreference: .latestPrompt
        )

        #expect(SessionCardPresentation.hasSessionTitle(session))
        #expect(automatic.titleText == "Original implementation work")
        #expect(explicitPrompt.titleText == "Now prepare the release notes")
    }

    @Test("An inactive session identifies the ended process below its title")
    func inactiveSessionShowsHistoryBelowTitle() {
        let session = UnifiedSession(id: "inactive-session", agentType: .claudeCode)
        session.presence = .inactive
        session.lastKnownStatus = .thinking
        session.sessionTitle = "Review the implementation"
        session.lastUserPrompt = "Review the implementation"

        let presentation = SessionCardPresentation.content(
            session: session,
            promptSource: .lastUserMessage
        )

        #expect(presentation.titleText == "Review the implementation")
        #expect(presentation.activityText == "\(L("Process ended")) · \(L("Thinking"))")
        #expect(presentation.metadataText == nil)
    }

    @Test("History remains the visible fallback when no title was saved")
    func historyFallbackWithoutTitle() {
        let source = UnifiedSession(id: "no-prompt", agentType: .codex)
        source.status = .done
        let restored = SessionSnapshot(session: source).makeRestoredSession()

        let presentation = SessionCardPresentation.content(
            session: restored,
            promptSource: .lastUserMessage
        )

        #expect(presentation.titleText == nil)
        #expect(presentation.activityText == "\(L("Last seen")) · \(L("Done"))")
        #expect(presentation.metadataText == nil)
    }

    @Test("Live context prioritizes active work, completion, then the latest prompt")
    func liveContextPriority() {
        let session = UnifiedSession(id: "live-session", agentType: .codex)
        session.sessionTitle = "Persist session cards"
        session.lastUserPrompt = "Add a snapshot assertion"
        session.lastAssistantMessage = "All assertions now pass"
        session.currentTool = ToolInfo(
            id: "tool-1",
            name: "Bash",
            summary: "swift test",
            input: [:],
            startedAt: .now,
            status: .running
        )

        var presentation = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage
        )
        #expect(presentation.activityText == "Bash — swift test")

        session.currentTool = nil
        session.status = .done
        presentation = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage
        )
        #expect(presentation.activityText == "All assertions now pass")

        session.status = .idle
        presentation = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage
        )
        #expect(presentation.activityText == "Add a snapshot assertion")
    }

    @Test("The final card row shows active subagents before the in-progress task")
    func finalRowPrefersSubagentsThenTask() {
        let session = UnifiedSession(id: "work-summary", agentType: .claudeCode)
        session.tasks = [
            AgentTask(id: "task-1", subject: "Render the active task", status: .inProgress)
        ]
        session.subagents = [
            SubagentRun(
                id: "subagent-1",
                agentType: "Explore",
                startedAt: .now,
                status: .running,
                hasExplicitId: true
            )
        ]

        var presentation = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage
        )
        #expect(presentation.activityText == L("Running \(1) subagents"))
        #expect(presentation.workText == "\(L("Subagents")) — Explore")

        session.subagents = []
        presentation = SessionCardPresentation.content(
            session: session,
            promptSource: .firstUserMessage
        )
        #expect(presentation.workText == "\(L("Tasks")) — Render the active task")
    }

    @Test("Only a respondable permission at the queue head gets a countdown")
    func countdownPermissionFollowsQueueHead() {
        let session = UnifiedSession(id: "countdown", agentType: .claudeCode)
        let permission = PermissionRequest(
            id: "permission",
            agentType: .claudeCode,
            sessionId: session.id,
            toolName: "Bash",
            toolInput: [:],
            toolUseId: "permission",
            timestamp: .now,
            canRespond: true
        )
        session.pendingInterruptions.enqueue(permission)

        #expect(
            SessionCardPresentation.countdownPermission(for: session)?.toolUseId
                == permission.toolUseId
        )

        session.pendingPermissions = [
            PermissionRequest(
                id: permission.id,
                agentType: permission.agentType,
                sessionId: permission.sessionId,
                toolName: permission.toolName,
                toolInput: permission.toolInput,
                toolUseId: permission.toolUseId,
                timestamp: permission.timestamp,
                canRespond: false
            )
        ]
        #expect(SessionCardPresentation.countdownPermission(for: session) == nil)

        session.pendingPermissions = []
        session.pendingQuestion = PendingQuestion(toolUseId: "question", questions: [])
        #expect(SessionCardPresentation.countdownPermission(for: session) == nil)
    }

    @Test("The mute icon is vertically centered with the session title")
    @MainActor
    func muteIconIsCenteredWithTitle() throws {
        let session = UnifiedSession(id: "muted-session", agentType: .claudeCode)
        session.status = .thinking
        session.cwd = "/tmp/MMMM"
        session.sessionTitle = "Review title placement"

        let hostingView = NSHostingView(
            rootView:
                SessionCardView(
                    session: session,
                    userState: SessionUserState(muted: true)
                )
                .frame(width: 360, height: 80, alignment: .topLeading)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 80)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let scale = CGFloat(bitmap.pixelsWide) / hostingView.bounds.width
        let iconBounds = try #require(
            visibleBounds(
                in: bitmap,
                xRange: 48..<62,
                yRange: 8..<28,
                brightnessThreshold: 0.14
            )
        )
        let titleBounds = try #require(
            visibleBounds(
                in: bitmap,
                xRange: 63..<115,
                yRange: 8..<28,
                brightnessThreshold: 0.5
            )
        )
        let centerDelta = abs(iconBounds.midY - titleBounds.midY) / scale

        #expect(
            // The symbol and the 12pt title share a centered SwiftUI frame. Their antialiased
            // pixel bounds differ slightly because the symbol has no text baseline.
            centerDelta <= 2,
            "Mute icon and title centers differ by \(centerDelta) pt"
        )
    }

    private func visibleBounds(
        in bitmap: NSBitmapImageRep,
        xRange: Range<CGFloat>,
        yRange: Range<CGFloat>,
        brightnessThreshold: CGFloat
    ) -> CGRect? {
        var bounds = CGRect.null
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let pixelXRange = Int(xRange.lowerBound * scale)..<Int(xRange.upperBound * scale)
        let pixelYRange = Int(yRange.lowerBound * scale)..<Int(yRange.upperBound * scale)

        for y in pixelYRange where y < bitmap.pixelsHigh {
            for x in pixelXRange where x < bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.deviceRGB)
                else { continue }

                if max(color.redComponent, color.greenComponent, color.blueComponent)
                    > brightnessThreshold
                {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }

        return bounds.isNull ? nil : bounds
    }
}
