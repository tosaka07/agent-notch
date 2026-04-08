import Defaults
import SwiftUI

enum TextSizePreference: String, Defaults.Serializable, CaseIterable, Sendable {
    case small
    case medium
    case large

    var label: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 1.0
        case .medium: 1.1
        case .large: 1.2
        }
    }

    /// Scale a base font size, rounding to nearest 0.5
    func scaled(_ base: CGFloat) -> CGFloat {
        (base * scale * 2).rounded() / 2
    }
}

extension Defaults.Keys {
    static let textSize = Key<TextSizePreference>("textSize", default: .small)
}
