import AppKit
import Foundation

/// Icons of the applications macOS currently uses for the URL schemes Agent Notch opens.
///
/// A destination button carries the icon of the app you land in, which is the same rule the terminal
/// jump already follows: the icon answers "where does this take me?" faster than a vendor logo can,
/// and it stays honest when the product ships under another name — `codex://` is usually owned by
/// ChatGPT.app.
///
/// Resolution goes through Launch Services and allocates an image, which is too much for a SwiftUI
/// body that re-runs on every session update, so a resolved icon is memoised per scheme. Only
/// successes are cached: a scheme with no registered app hides its button anyway, so nothing asks
/// again until an app claims it.
@MainActor
final class SchemeApplicationIcons {
    typealias ApplicationResolver = (URL) -> URL?
    typealias IconLoader = (URL) -> NSImage?

    static let shared = SchemeApplicationIcons()

    private let resolveApplication: ApplicationResolver
    private let loadIcon: IconLoader
    private var iconsByScheme: [String: NSImage] = [:]

    init(
        applicationURLFor resolveApplication: @escaping ApplicationResolver = {
            NSWorkspace.shared.urlForApplication(toOpen: $0)
        },
        loadIcon: @escaping IconLoader = { NSWorkspace.shared.icon(forFile: $0.path) }
    ) {
        self.resolveApplication = resolveApplication
        self.loadIcon = loadIcon
    }

    /// The icon of the app registered for this URL's scheme, or nil when there is none to draw.
    ///
    /// The scheme is the cache key rather than the whole URL: every session of one agent resolves to
    /// the same application, so per-session lookups would repeat identical work.
    func icon(for url: URL) -> NSImage? {
        guard let scheme = url.scheme, !scheme.isEmpty else { return nil }
        if let cached = iconsByScheme[scheme] { return cached }

        guard let applicationURL = resolveApplication(url),
            let icon = loadIcon(applicationURL)
        else {
            return nil
        }
        iconsByScheme[scheme] = icon
        return icon
    }
}
