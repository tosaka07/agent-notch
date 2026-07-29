import SwiftUI

/// A guard that ignores taps for `delay` seconds after appearing.
///
/// Because `NotchHostingView.acceptsFirstMouse` is true, buttons in the panel fire on the very
/// first click even while inactive. Right after the panel auto-expands on an incoming permission
/// request, a mouse that happens to be near the Approve button could complete an unintended
/// one-click approval — so this applies only to irreversible action buttons (Approve/Deny,
/// sending an answer to a question). It is not applied to ordinary card taps or list operations.
private struct ArmedAfterDelay: ViewModifier {
    let delay: TimeInterval
    @State private var isArmed = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(isArmed)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                    isArmed = true
                }
            }
    }
}

extension View {
    /// Ignores taps for `delay` (default 0.3s) after appearing.
    /// Use only on irreversible action buttons such as Approve/Deny.
    func armedAfter(_ delay: TimeInterval = 0.3) -> some View {
        modifier(ArmedAfterDelay(delay: delay))
    }
}
