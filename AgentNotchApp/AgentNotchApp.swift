import AgentNotch
import SwiftUI

/// The executable's entry point, and nothing else.
///
/// This file is shared between the SwiftPM executable and the Xcode target: everything the app
/// actually does lives in the `AgentNotch` library, which both of them link. Keeping `@main`
/// here is what lets Xcode build the shipped `.app` — a SwiftPM executable target cannot be
/// linked into an Xcode application target.
@main
struct AgentNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
