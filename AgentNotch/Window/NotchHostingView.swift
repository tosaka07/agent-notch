import AppKit
import SwiftUI

/// Simple NSHostingView subclass. clipShape on the SwiftUI side controls hit testing.
/// No hitTestRect or ignoresMouseEvents toggling needed.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// パネルがキーウィンドウでない状態（＝他アプリがアクティブな通常時）でも、
    /// 最初の 1 クリックでボタン等の SwiftUI アクションを発火させる。
    /// デフォルト実装（false）だと、1 回目のクリックはウィンドウをキーにするだけで
    /// 消費され、ボタンの action は 2 回目のクリックまで届かない。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
