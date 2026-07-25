import SwiftUI

/// Agent Notch のタイポグラフィトークン。標準フォントのみ使用（bundle なし）。
///
/// このファイルは 2 系統に分かれる:
/// - `DSTypography`（このトップレベル）: **notch 独自言語**。compact モードの
///   DotMatrix / PixelCounter / TickerText や、展開一覧のカードなど「工業計器」的な
///   見た目を担う。ここは今回のネイティブ化の対象外（現状維持）。
/// - `DSTypography.Native`: **パネル用 semantic native タイポグラフィ**。
///   選択画面（Permission/Question banner）・詳細画面など「展開後、OS の UI として
///   振る舞うべき」箇所はすべてこちらを使う。macOS の semantic text style 階層
///   （headline/body/callout/subheadline/footnote/caption 相当）に対応するポイント数を
///   基準とし、`Defaults[.textSize]`（`TextSizePreference.scale`）を掛けて全体を
///   一貫してスケールする。
///
/// # 使い分け（独自言語側）
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

    /// パネル（選択画面・詳細画面）用の semantic native type scale。
    ///
    /// | role        | base pt | weight    | 用途                                     |
    /// |-------------|---------|-----------|------------------------------------------|
    /// | headline    | 13      | semibold  | セッションタイトル、バナー見出し           |
    /// | body        | 13      | regular   | 本文（チャット markdown 等）              |
    /// | callout     | 12      | regular   | ボタンラベル、質問文                       |
    /// | subheadline | 11      | regular   | オプションラベル、サブテキスト             |
    /// | footnote    | 10      | regular   | ツール名 / パス / セクション見出し         |
    /// | caption     | 9       | regular   | メタ情報（時刻・トークン数・件数）         |
    /// | caption2    | 8       | regular   | 最小の補助ラベル                           |
    ///
    /// mono* は上記と同じ base pt で `design: .monospaced`。コード・パス・
    /// tool 名など「等幅であるべき」情報にのみ使う（地の文は non-mono）。
    ///
    /// 各関数は `scale`（= `Defaults[.textSize].scale`）を受け取り、
    /// 呼び出し側で `@Default(.textSize)` の値をそのまま渡すだけで全体に
    /// 一貫したスケーリングが効く。
    enum Native {
        static func headline(_ scale: CGFloat = 1) -> Font {
            .system(size: round(13 * scale), weight: .semibold)
        }

        static func body(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(13 * scale), weight: weight)
        }

        static func callout(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(12 * scale), weight: weight)
        }

        static func subheadline(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(11 * scale), weight: weight)
        }

        static func footnote(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(10 * scale), weight: weight)
        }

        static func caption(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(9 * scale), weight: weight)
        }

        static func caption2(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(8 * scale), weight: weight)
        }

        static func monoCallout(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(12 * scale), weight: weight, design: .monospaced)
        }

        static func monoSubheadline(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(11 * scale), weight: weight, design: .monospaced)
        }

        static func monoFootnote(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(10 * scale), weight: weight, design: .monospaced)
        }

        static func monoCaption(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(9 * scale), weight: weight, design: .monospaced)
        }

        static func monoCaption2(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
            .system(size: round(8 * scale), weight: weight, design: .monospaced)
        }

        private static func round(_ value: CGFloat) -> CGFloat {
            (value * 2).rounded() / 2
        }
    }
}
