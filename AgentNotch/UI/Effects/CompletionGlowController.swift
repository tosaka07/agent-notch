import SwiftUI

/// 完了グロウ演出の state と操作をカプセル化する。
///
/// - `intensity` / `color` は Overlay View が読み取る。
/// - `trigger(color:)` は短いフェードインと 8 秒後のフォールバックフェードアウトを予約する（通知が表示されない経路でも消えるように）。
/// - `cancel()` は即時に 0 にする。呼び出し側が `withAnimation { glow.cancel() }` のように包むと
///   その transaction に乗ってアニメーションされる。
@MainActor
@Observable
final class CompletionGlowController {
    var intensity: CGFloat = 0
    var color: Color = .green
    /// glow と一緒に短時間だけ表示するラベル（repo 名など）。
    /// 選択画面（expanded / sessionDetail）表示中に裏で別セッションが完了した際、
    /// どのセッションが光っているか分かるようにする（#3）。
    var label: String?

    private var labelTask: Task<Void, Never>?

    func trigger(color: Color, label: String? = nil) {
        self.color = color
        withAnimation(.easeOut(duration: 0.4)) {
            intensity = 1
        }

        if let label {
            self.label = label
            labelTask?.cancel()
            labelTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.6)) {
                    self.label = nil
                }
            }
        }

        // 通知が発生しない経路（expanded モード等）のフォールバック
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, intensity > 0 else { return }
            withAnimation(.easeOut(duration: 1.5)) {
                self.intensity = 0
            }
        }
    }

    func cancel() {
        intensity = 0
        label = nil
        labelTask?.cancel()
        labelTask = nil
    }
}
