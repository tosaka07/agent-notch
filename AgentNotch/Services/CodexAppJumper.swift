import AgentNotchCore
import AppKit
import Foundation

/// Opens a local Codex thread in the desktop app through its public deep-link contract.
///
/// The desktop product may be installed as `ChatGPT.app`, but OpenAI keeps the `codex://`
/// scheme for compatibility. Resolving the scheme instead of hard-coding an app path or bundle
/// identifier also survives that product rename.
@MainActor
enum CodexAppJumper {
    typealias ApplicationResolver = (URL) -> URL?
    typealias URLOpener = (URL) -> Bool

    /// Builds the canonical deep link for a Codex session.
    ///
    /// Agent Notch stores Codex's hook `session_id` as `UnifiedSession.id`. Root sessions use that
    /// same value as their technical thread ID. Subagent hooks are intentionally folded into their
    /// parent session by Codex, so the resulting card opens the parent thread.
    static func deepLink(for session: UnifiedSession) -> URL? {
        guard session.agentType == .codex else { return nil }
        return deepLink(threadId: session.id)
    }

    static func deepLink(threadId: String) -> URL? {
        guard !threadId.isEmpty,
            threadId != "unknown",
            threadId != ".",
            threadId != "..",
            threadId.rangeOfCharacter(
                from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
            ) == nil
        else {
            return nil
        }

        // A thread ID is one URL path component. Keep only RFC 3986 unreserved characters literal
        // so a future ID containing `/`, `?`, or `#` cannot change the destination route.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encodedThreadId = threadId.addingPercentEncoding(withAllowedCharacters: unreserved)
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.percentEncodedPath = "/\(encodedThreadId)"
        return components.url
    }

    /// The action is shown only when macOS currently has an app registered for the public scheme.
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
    /// nil falls the button back to the Codex mark.
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
            Log.panel.error("Codex app jump rejected an invalid session ID")
            return false
        }
        guard openURL(url) else {
            Log.panel.error("Codex app jump failed: no application accepted the deep link")
            return false
        }

        Log.panel.info("opened Codex app thread")
        onOpened()
        return true
    }
}
