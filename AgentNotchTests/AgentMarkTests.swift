import CoreGraphics
import Foundation
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

/// 埋め込んだ公式ロゴの SVG パスが、自前パーサで正しく閉じた図形になるかを検証する。
///
/// ロゴは「描けているか」を目で見るしかないが、**パースが破綻していないこと**は
/// 数値で確かめられる: bounding box が viewBox の想定内に収まり、指定した矩形に
/// アスペクト比を保って収まり、コマンドを取り違えていない（＝面積が極端でない）。
@Suite("Agent Mark SVG Tests")
@MainActor
struct AgentMarkTests {
    @Test("Claude のパスは viewBox 125 角に収まる")
    func claudePathFitsViewBox() {
        let path = SVGPathParser.path(from: AgentMarkPath.claude)
        #expect(!path.isEmpty)
        let box = path.boundingRect
        // 元の SVG は 0〜125 の範囲（viewBox 0 0 125 125）。
        #expect(box.minX >= -0.01)
        #expect(box.minY >= -0.01)
        #expect(box.maxX <= 125.01)
        #expect(box.maxY <= 125.01)
        // ほぼ正方形のシンボル。極端に潰れていたらコマンドを取り違えている。
        #expect(abs(box.width - box.height) < 2)
    }

    @Test("OpenAI Blossom のパスは viewBox の中央に本体が収まる")
    func openAIPathIsCentered() {
        let path = SVGPathParser.path(from: AgentMarkPath.openAI)
        #expect(!path.isEmpty)
        let box = path.boundingRect
        // viewBox は 716 角だが、ロゴ本体は中央 183〜533 に収まっている。
        #expect(box.minX > 180)
        #expect(box.maxX < 536)
        #expect(abs(box.width - box.height) < 2)
    }

    /// `AgentMarkShape` は viewBox ではなく**実寸**で正規化する。
    /// OpenAI のように viewBox に余白があるロゴでも、他のロゴと同じ大きさに見える必要がある。
    @Test("与えた矩形にアスペクト比を保って収まる")
    func shapeFitsGivenRect() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        for commands in [AgentMarkPath.claude, AgentMarkPath.openAI] {
            let box = AgentMarkShape(commands: commands).path(in: rect).boundingRect
            #expect(box.width <= 20.01)
            #expect(box.height <= 20.01)
            // 余白ぶん縮むことなく、短辺いっぱいまで使う。
            #expect(max(box.width, box.height) > 19.5)
            // 矩形の中央に置かれる。
            #expect(abs(box.midX - rect.midX) < 0.01)
            #expect(abs(box.midY - rect.midY) < 0.01)
        }
    }

    /// パーサが対応するコマンドの取りこぼしを防ぐ回帰テスト。
    /// 相対座標・繰り返し引数・区切りとしての負符号を含む式を組み立てて確かめる。
    @Test("M/L/H/V/C/Z と相対座標、負符号区切りを解釈する")
    func parsesSupportedCommands() {
        // 10,10 から 20,10 → 20,20 → 10,20 と回って閉じる正方形を、
        // 絶対・相対・H/V を混ぜて書く。
        let square = SVGPathParser.path(from: "M10 10H20V20h-10Z")
        #expect(square.boundingRect == CGRect(x: 10, y: 10, width: 10, height: 10))

        // 区切りとしての負符号（`L10-5` = 10, -5）。
        let negative = SVGPathParser.path(from: "M0 0L10-5Z")
        #expect(negative.boundingRect == CGRect(x: 0, y: -5, width: 10, height: 5))

        // 繰り返し引数（`L` に 2 組）。
        let polyline = SVGPathParser.path(from: "M0 0L5 5 10 0Z")
        #expect(polyline.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 5))

        // 未対応コマンド（円弧 A）が来ても落ちない。
        let withArc = SVGPathParser.path(from: "M0 0L10 0A5 5 0 0 1 0 0Z")
        #expect(!withArc.isEmpty)
    }
}
