import SwiftUI

/// Color tokens for the Agent Notch design system.
///
/// # Usage rules
/// - Never use `signal.*` as an area-based background color (dots / underbars / glows /
///   single-character badges only)
/// - Two colors lit at once is fine; three is not
/// - Color is secondary to state — the state must still read from the dot pattern's shape
///   with the color gone
enum DSColors {
    // MARK: - Base

    static let canvas = Color.black
    static let surface = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.10)
    /// The fill AppKit gives a `.bordered` button — measured, not guessed (see
    /// `SessionDetailSurfaceTests`). Use it for anything that has to read as a
    /// sibling of the panel's system buttons while not being one, such as a
    /// control whose surface has to survive growing into a container.
    static let control = Color.white.opacity(0.08)

    // MARK: - Scrim (the dark veil layered over a surface)
    //
    // The panel and cards are Liquid Glass (`glassEffect`), and the surfaces within them are
    // black layered over material. Too much black kills the texture and leaves "just a black
    // slab"; too little and dots and hairlines lose to the background. Hierarchy comes from
    // **the difference between the glass (panel, cards) and the scrim (value surfaces,
    // pressable surfaces)**, so tune these values as a set.

    /// Scrim for cards inside the panel (a fallback for when Reduce Transparency is on).
    static let cardScrimOpacity: Double = 0.42
    /// Scrim for content cards placed directly on the glass panel.
    static let panelCardScrimOpacity: Double = 0.06
    /// Scrim for "value-showing surfaces" inside a card (commands, tool output).
    /// One step darker than the card, to sit behind it.
    static let insetScrimOpacity: Double = 0.52
    /// Scrim for "pressable surfaces" inside a card (option rows).
    ///
    /// On a glass card, sinking something with black puts it behind rather than in front. The
    /// scrim only goes as far as damping the material's whiteness; bringing it forward is done
    /// with white (`surface`). A pressable thing that looks sunken does not invite a touch.
    static let raisedScrimOpacity: Double = 0.1
    /// Minimal scrim that keeps the Liquid Glass panel readable and gives the
    /// entire visible panel one nonzero rendered surface.
    static let glassPanelScrimOpacity: Double = 0.12

    // MARK: - Ink (text / primary dots)

    static let ink = Color.white
    static let inkDim = Color.white.opacity(0.40)
    static let inkMute = Color.white.opacity(0.22)
    /// For empty dots / grid ghosts.
    static let inkGhost = Color.white.opacity(0.08)

    // MARK: - Schematic lines

    static let lineFaint = Color.white.opacity(0.06)
    static let lineDefault = Color.white.opacity(0.12)
    static let lineStrong = Color.white.opacity(0.24)

    // MARK: - Signal (semantic state colors)
    // Extended from a monochrome + amber accent base to six colors, to cover Agent Notch's
    // many states.

    /// idle / starting
    static let signalIdle = Color(red: 0.545, green: 0.545, blue: 0.545)  // #8B8B8B
    /// thinking / compacting
    static let signalThinking = Color(red: 0.000, green: 0.898, blue: 1.000)  // #00E5FF
    /// tool running / subagent running
    static let signalWorking = Color.white
    /// permission waiting
    static let signalAlert = Color(red: 1.000, green: 0.722, blue: 0.000)  // #FFB800
    /// waiting for an answer — still attention-worthy, but distinct from permission approval
    static let signalQuestion = Color(red: 1.000, green: 0.541, blue: 0.239)  // #FF8A3D
    /// error / stop failure
    static let signalError = Color(red: 1.000, green: 0.231, blue: 0.188)  // #FF3B30
    /// done / completed
    static let signalDone = Color(red: 0.204, green: 0.831, blue: 0.600)  // #34D399
    /// plan mode / awaiting plan review (the ExitPlanMode confirmation)
    static let signalPlan = Color(red: 0.635, green: 0.510, blue: 1.000)  // #A282FF
}
