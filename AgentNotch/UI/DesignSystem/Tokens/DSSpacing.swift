import SwiftUI

/// パネル（選択画面・詳細画面）用の 8pt グリッドに基づく余白トークン。
///
/// notch 独自言語側（compact モード）は密度優先の細かい値をそのまま使ってよいが、
/// パネル内の新規/改修コードは以下から選んで余白の一貫性を保つこと。
enum DSSpacing {
    /// 4pt — インライン要素間の最小間隔（アイコンとラベルなど）
    static let xs: CGFloat = 4
    /// 8pt — グリッド単位。行内 spacing の基本値
    static let sm: CGFloat = 8
    /// 12pt — カード内の縦 spacing
    static let md: CGFloat = 12
    /// 16pt — セクション間、カードの外側パディング
    static let lg: CGFloat = 16
    /// 24pt — 大きめのセクション間隔
    static let xl: CGFloat = 24
}
