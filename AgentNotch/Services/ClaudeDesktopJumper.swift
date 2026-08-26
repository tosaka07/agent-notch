import AgentNotchCore
import AppKit
import Foundation

/// Opens a Claude Code session that the Claude desktop app is running, inside that app.
///
/// The desktop app registers the `claude://` scheme and routes deep links by host and by the first
/// path segment. Only a segment it knows is navigated; anything else is handed to the web layer and
/// silently dropped. `claude-code-desktop/<session>` is the recognised entry point for a Code
/// session, and the app redirects it internally to that session's own route — which is why the link
/// is not addressed to the internal route directly.
///
/// Resolving the scheme rather than launching a hard-coded bundle identifier keeps the action
/// hidden on machines where the desktop app is not installed.
@MainActor
enum ClaudeDesktopJumper {
    typealias ApplicationResolver = (URL) -> URL?
    typealias URLOpener = (URL) -> Bool

    /// Builds the deep link for a session the desktop app owns.
    ///
    /// `UnifiedSession.id` is the CLI `session_id` the hook reports, which the app cannot route on;
    /// the destination comes from the resolved desktop identifier instead.
    static func deepLink(for session: UnifiedSession) -> URL? {
        guard session.agentType == .claudeCode,
            let desktopSessionId = session.claudeDesktopSessionId
        else {
            return nil
        }
        return deepLink(desktopSessionId: desktopSessionId)
    }

    static func deepLink(desktopSessionId: String) -> URL? {
        guard !desktopSessionId.isEmpty,
            desktopSessionId != ".",
            desktopSessionId != "..",
            desktopSessionId.rangeOfCharacter(
                from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
            ) == nil
        else {
            return nil
        }

        // The identifier is one URL path component. Keep only RFC 3986 unreserved characters
        // literal so an ID containing `/`, `?`, or `#` cannot rewrite the route.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard
            let encodedSessionId = desktopSessionId.addingPercentEncoding(
                withAllowedCharacters: unreserved
            )
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "claude"
        components.host = "claude.ai"
        components.percentEncodedPath = "/claude-code-desktop/\(encodedSessionId)"
        return components.url
    }

    /// The action is shown only when macOS currently has an app registered for the scheme.
    static func canJump(to session: UnifiedSession) -> Bool {
        canJump(
            to: session,
            applicationURLFor: { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        )
    }

    static func canJump(
        to session: UnifiedSession,
        applicationURLFor resolveApplication: ApplicationResolver
    ) -> Bool {
        guard let url = deepLink(for: session) else { return false }
        return resolveApplication(url) != nil
    }

    /// The icon of the app that will receive the jump, so the button names its own destination.
    /// nil falls the button back to the Claude mark.
    static func applicationIcon(
        for session: UnifiedSession,
        icons: SchemeApplicationIcons = .shared
    ) -> NSImage? {
        guard let url = deepLink(for: session) else { return nil }
        return icons.icon(for: url)
    }

    /// Opens the destination and closes the notch only after Launch Services accepts the request.
    @discardableResult
    static func jump(
        to session: UnifiedSession,
        openURL: URLOpener = { NSWorkspace.shared.open($0) },
        onOpened: () -> Void = {
            NotificationCenter.default.post(name: .agentNotchClosePanel, object: nil)
        }
    ) -> Bool {
        guard let url = deepLink(for: session) else {
            Log.panel.error("Claude desktop jump rejected a session with no desktop identifier")
            return false
        }
        guard openURL(url) else {
            Log.panel.error("Claude desktop jump failed: no application accepted the deep link")
            return false
        }

        Log.panel.info("opened Claude desktop session")
        onOpened()
        return true
    }
}
