import SwiftUI

/// The state glyphs, in reading order, with the words for what they mean.
///
/// # Why this is shared
/// Both the Settings reference and the onboarding tour teach the same vocabulary. Kept as two
/// lists they would drift — a glyph added to one, renamed in the other — and the notch's whole
/// claim is that one shape always means one thing. This is the single list; callers take the
/// fields they have room for.
///
/// Order runs from "nothing is happening" to "something needs you": standby, thinking, working,
/// subagents, then the states that interrupt.
enum GlyphLegend {
    struct Entry: Identifiable {
        let state: Glyph.State
        /// The short name. The only field small surfaces (the tour's grid) show.
        let title: String
        /// Which session states map onto this glyph.
        let sessionStates: String
        /// What the motion is saying.
        let explanation: String

        var id: String { title }
    }

    static let all: [Entry] = [
        Entry(
            state: .standby,
            title: L("Standby"),
            sessionStates: L("Starting, idle, or session ended"),
            explanation: L("A breathing ring means the session is not actively working.")
        ),
        Entry(
            state: .thinking,
            title: L("Thinking"),
            sessionStates: L("Thinking or compacting context"),
            explanation: L("A travelling wave means the agent is reasoning or preparing context.")
        ),
        Entry(
            state: .working,
            title: L("Working"),
            sessionStates: L("Running a tool"),
            explanation: L("A pulsing core means a tool call is in progress.")
        ),
        Entry(
            state: .swarm(active: 5),
            title: L("Subagents"),
            sessionStates: L("One or more subagents running"),
            explanation: L("Each filled square represents an active subagent, up to nine.")
        ),
        Entry(
            state: .alert,
            title: L("Approval"),
            sessionStates: L("Waiting for permission approval"),
            explanation: L("An exclamation mark blinks until you approve or deny the request.")
        ),
        Entry(
            state: .question,
            title: L("Question"),
            sessionStates: L("Waiting for an answer"),
            explanation: L("A question mark blinks until you answer the agent.")
        ),
        Entry(
            state: .planReview,
            title: L("Plan review"),
            sessionStates: L("Waiting for plan approval"),
            explanation: L("Three lines identify the special approval shown when leaving plan mode.")
        ),
        Entry(
            state: .complete,
            title: L("Complete"),
            sessionStates: L("Turn finished"),
            explanation: L(
                "A check mark appears when the agent has finished and is waiting for your next prompt."
            )
        ),
        Entry(
            state: .fault,
            title: L("Fault"),
            sessionStates: L("An error interrupted the work"),
            explanation: L("A cross flickers to show that the session stopped because of an error.")
        ),
    ]
}
