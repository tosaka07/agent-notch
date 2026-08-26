import SwiftUI

/// Contents of the pill shown briefly alongside the completion glow.
///
/// When another session finishes in the background while a list screen (expanded /
/// sessionDetail) is up, this says which session is glowing. It carries the sessionId too, so a
/// tap can jump to that session.
struct CompletionPill: Equatable {
    var label: String
    var sessionId: String
}

/// Encapsulates the state and operations of the completion glow effect.
///
/// - `intensity` / `color` are read by the overlay view.
/// - `trigger(color:)` schedules a short fade-in plus a fallback fade-out after 8 seconds, so it
///   still disappears on paths where no notification is shown.
/// - `cancel()` drops to 0 immediately. Wrapping the call as
///   `withAnimation { glow.cancel() }` animates it on that transaction.
@MainActor
@Observable
final class CompletionGlowController {
    var intensity: CGFloat = 0
    var color: Color = .green
    /// The pill shown briefly alongside the glow (repo name + sessionId).
    var pill: CompletionPill?

    private var pillTask: Task<Void, Never>?

    func trigger(color: Color, pill: CompletionPill? = nil) {
        self.color = color
        withAnimation(.easeOut(duration: 0.4)) {
            intensity = 1
        }

        if let pill {
            self.pill = pill
            pillTask?.cancel()
            pillTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.6)) {
                    self.pill = nil
                }
            }
        }

        // Fallback for paths that raise no notification (expanded mode, etc.)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, intensity > 0 else { return }
            withAnimation(.easeOut(duration: 1.5)) {
                self.intensity = 0
            }
        }
    }

    func cancel() {
        intensity = 0
        pill = nil
        pillTask?.cancel()
        pillTask = nil
    }
}
