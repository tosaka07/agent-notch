import AgentNotchCore
import SwiftUI

@MainActor
@Observable
final class NotchViewModel {
    var mode: NotchMode = .compact {
        didSet {
            if mode != oldValue {
                Log.panel.info("Mode: \(oldValue) → \(mode)")
            }
        }
    }
    var isHovering: Bool = false {
        didSet {
            if isHovering != oldValue {
                Log.panel.debug("Hovering: \(isHovering)")
            }
        }
    }

    var physicalNotchWidth: CGFloat
    var physicalNotchHeight: CGFloat
    var hasActivity: Bool = false
    /// この画面に物理 notch があるか。
    ///
    /// 物理 notch がある画面では、パネル中央（notch 実寸の幅）は**物理的に隠れて見えない**。
    /// そこに何かを描いても無駄なので、compact の中央 ticker は notch なし
    /// （フローティングバー表示）のときだけ出す。
    var hasPhysicalNotch: Bool

    init(
        notchSize: CGSize = CGSize(width: 224, height: 38),
        initialMode: NotchMode = .compact,
        hasPhysicalNotch: Bool = true
    ) {
        self.physicalNotchWidth = notchSize.width
        self.physicalNotchHeight = notchSize.height
        self.mode = initialMode
        self.hasPhysicalNotch = hasPhysicalNotch
    }

    private let notchCornerMargin: CGFloat = 6

    var sideWidth: CGFloat {
        max(0, physicalNotchHeight - 12) + 10
    }

    private var compactWidth: CGFloat {
        physicalNotchWidth + notchCornerMargin + (2 * sideWidth)
    }

    var notchWidth: CGFloat {
        switch mode {
        case .compact:
            return isHovering ? compactWidth + 16 : compactWidth
        case .notification:
            return compactWidth
        case .expanded: return 520
        case .sessionDetail: return 620
        // 使用量ページは一覧と同じ幅。ウィンドウ単位の内訳を縦に積むだけなので広げる必要はない。
        case .usage: return 520
        }
    }

    var notificationCount: Int = 0

    private let notificationItemHeight: CGFloat = 42

    var notchHeight: CGFloat {
        switch mode {
        case .compact:
            return isHovering ? physicalNotchHeight + 6 : physicalNotchHeight
        case .notification:
            let count = max(notificationCount, 1)
            return physicalNotchHeight + notificationItemHeight * CGFloat(count) + 6
        case .expanded:
            return 380
        case .sessionDetail:
            return 500
        case .usage:
            return 440
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .compact, .notification: 6
        case .expanded, .sessionDetail, .usage: 12
        }
    }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .compact: 14
        case .notification: 16
        case .expanded, .sessionDetail, .usage: 24
        }
    }

    func toggle() {
        switch mode {
        case .compact, .notification: mode = .expanded
        case .expanded: mode = .compact
        // 詳細系ページからは一覧に戻る（トグルは「一段戻る」として振る舞う）。
        case .sessionDetail, .usage: mode = .expanded
        }
    }

    func close() { mode = .compact }
    func showSession(_ id: String) { mode = .sessionDetail(sessionId: id) }
    func showUsage() { mode = .usage }
    func backToList() { mode = .expanded }
}
