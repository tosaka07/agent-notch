import Foundation

/// Locates a SwiftPM resource bundle inside whatever container this build ended up in.
///
/// This exists because `Bundle.module` cannot be used from an app that ships as a `.app`.
/// SwiftPM generates an accessor that looks in exactly two places: directly under
/// `Bundle.main.bundleURL`, and the absolute path of the build directory baked in at compile
/// time. Inside a bundle neither one holds — resources belong in `Contents/Resources`, and the
/// build path only exists on the machine that compiled the binary. So `Bundle.module` silently
/// falls back to the build directory for whoever built the app and calls `fatalError` on every
/// other machine, which is a crash that testing the app locally can never surface.
///
/// Every resource lookup in this package must go through here rather than `Bundle.module`.
public enum ResourceBundle {
    /// Anchors `Bundle(for:)` on the binary that contains this package's code, which is how the
    /// bundle is found when the tests run and `Bundle.main` is the xctest runner instead.
    private final class Finder {}

    /// - Parameter name: the bundle's base name, e.g. `AgentNotch_AgentNotchCore`.
    /// - Returns: the bundle, or `nil` when it is genuinely absent. Callers fall back to
    ///   `Bundle.main`, where a missing localization degrades to the key rather than a crash.
    public static func locate(_ name: String) -> Bundle? {
        let fileName = "\(name).bundle"
        let enclosing = Bundle(for: Finder.self)

        let candidates: [URL?] = [
            // A `.app`: the bundle sits in `Contents/Resources` next to the other resources.
            Bundle.main.resourceURL,
            // `swift run` and the CLI: the executable's own directory.
            Bundle.main.bundleURL,
            // Loaded from a framework or an xctest bundle.
            enclosing.resourceURL,
            enclosing.bundleURL,
            // `swift test`: SwiftPM leaves the resource bundles beside the xctest bundle
            // rather than inside it.
            enclosing.bundleURL.deletingLastPathComponent(),
        ]

        for directory in candidates.compactMap({ $0 }) {
            let candidate = directory.appendingPathComponent(fileName)
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return nil
    }

    /// Resources owned by `AgentNotchCore`.
    public static let core = locate("AgentNotch_AgentNotchCore") ?? .main
}
