import SwiftUI

/// Agent Notch のタイポグラフィトークン。標準フォントのみ使用（bundle なし）。
///
/// # 使い分け
/// - `display`: 大ラベル（`WAITING` / `#01`）。重さで工業感を出す。28–40pt。
/// - `mono`: tool 名、値、パス、日本語補助。10–12pt。
/// - `caption`: メタラベル（`PROJECT` / `MODEL`）。9pt uppercase + tracking +0.08em 前提。
///
/// pixel 表現（0-9 数字、状態ドット）は `PixelGrid` / `DotMatrix` / `PixelCounter` が
/// Canvas で bitmap 描画する。フォントには依存しない。
enum DSTypography {
    /// Display: SF Pro Black。
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }

    /// Mono: SF Mono。
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Caption: SF Pro Regular。
    static func caption(_ size: CGFloat = 9) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}
