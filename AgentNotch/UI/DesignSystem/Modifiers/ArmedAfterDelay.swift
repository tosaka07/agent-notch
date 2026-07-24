import SwiftUI

/// 表示されてから `delay` 秒間はタップ判定を無視するガード。
///
/// `NotchHostingView.acceptsFirstMouse` を true にしたことで（#8）、パネル内の
/// ボタンは非アクティブ状態でも 1 クリック目で発火するようになった。permission
/// リクエスト到着でパネルが自動展開された直後、たまたまマウスが Approve ボタン
/// 付近にあると意図しないワンクリック承認が成立し得るため、取り消せない
/// アクションボタン（Approve/Deny、質問への回答送信など）にのみ適用する。
/// 通常のカードタップや一覧操作には適用しない。
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
    /// 表示されてから `delay`（デフォルト 0.3 秒）はタップを無視する。
    /// Approve/Deny のような取り消せないアクションボタンにのみ使うこと。
    func armedAfter(_ delay: TimeInterval = 0.3) -> some View {
        modifier(ArmedAfterDelay(delay: delay))
    }
}
