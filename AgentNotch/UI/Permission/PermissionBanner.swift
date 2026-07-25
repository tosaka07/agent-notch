import AgentNotchCore
import Defaults
import KeyboardShortcuts
import SwiftUI

/// tool 実行の許可確認バナー。
///
/// # 見え方の方針（モック 3a のタイムラインと地続きにする）
/// `.borderedProminent` などの system control で組むと、黒地 + ドットグリフのタイムラインの
/// 中に **OS のダイアログが割り込んだように**見え、パネルの一部として信用しづらい。
/// そこで詳細画面の他の要素と同じ語彙で組む:
/// - 見出しは mono 大文字 + tracking（SF Symbol は使わない）
/// - tool の中身は `ToolLogRow` と同じ「黒地 + 細い枠 + 等幅」のブロック
/// - 決定ボタンは `GlyphButton`（枠と文字で階層を作る）
///
/// # 置き場所と階層
/// 詳細画面の下端に固定される（`SessionDetailView` の `safeAreaInset`）。
/// **notch パネルの中に置かれたもう 1 枚の面**として見せる。面・角丸・意味色の縁・影は
/// `notchCard` が持つ（パネルより一段明るい暗色の半透明。詳細は `NotchCard` 参照）。
///
/// # 見出しにグリフを置かない
/// 承認待ちは**パネル上部の状態グリフが既に `!` で示している**。カードの中にもう一度
/// 同じグリフを出すと、同じ状態が二重に表示されているように見える。ここでは
/// mono 大文字の見出しと tool 名だけで「何の決定か」を語る。
///
/// Return で Approve、Esc で Deny（`.defaultAction` / `.cancelAction`）は維持する。
struct PermissionBanner: View {
    let permission: PermissionRequest
    var onApprove: () -> Void
    var onDeny: () -> Void
    /// 失効バナー（canRespond=false）を閉じる。
    var onDismiss: () -> Void = {}

    @Default(.textSize) private var textSize
    /// パネルがキーウィンドウか。キーヒント（⏎ / esc）を出すかの判定に使う。
    @Environment(\.controlActiveState) private var controlActiveState

    /// どの決定が押されたか。押下演出のあいだだけ非 nil。
    @State private var resolution: Resolution?

    private enum Resolution { case approve, deny, dismiss }

    /// 押されてから実際に応答を送るまでの間。押した手応えを見せるための猶予。
    private let resolveDelay: Duration = .milliseconds(220)

    private var scale: CGFloat { textSize.scale }
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// 応答できるかで意味色を切り替える。失効は「もう届かない」= エラー側の意味。
    private var accent: Color {
        permission.canRespond ? DSColors.signalAlert : DSColors.signalError
    }

    /// キーヒントの表記。
    ///
    /// `NotchPanel` は `.nonactivatingPanel` なので、**バナーが出た直後はキーウィンドウでは
    /// ない**（パネルを一度クリックすると key になり、そこから ⏎ / esc が効く）。
    /// フォーカスが無い状態で ⏎ と書くと、押しても効かない操作を約束することになり、
    /// 実際には裏で作業していたターミナルに改行が入ってしまう。
    ///
    /// そこで**フォーカスが無いときはグローバルホットキーの方を出す**。こちらはアプリが
    /// 非アクティブでも効く（`NSApp.activate` でフォーカスを奪う手は採らない。承認は
    /// 取り消せない操作なので、タイプ中の文字が消えたり打った Enter がそのまま承認に
    /// なる方が危険）。
    private func keyHint(local: String, global: KeyboardShortcuts.Name) -> String? {
        if controlActiveState == .key { return local }
        return KeyboardShortcuts.getShortcut(for: global)?.description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            headline

            // description は「何をしようとしているか」の要約なので、コマンドと同じ
            // 黒地のブロックに入れるとシェルの出力に見えてしまう。読み物として
            // ブロックの外に、等幅ではない書体で置く。
            if let summary = permission.toolInput["description"], !summary.isEmpty {
                Text(summary)
                    .font(DSTypography.Native.callout(scale))
                    .foregroundStyle(DSColors.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !permission.canRespond {
                Text("この決定はもう届けられません。ターミナルで直接応答してください。")
                    .font(DSTypography.Native.caption(scale))
                    .foregroundStyle(DSColors.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            inputBlock

            HStack(spacing: DSSpacing.sm) {
                Spacer(minLength: 0)
                if permission.canRespond {
                    GlyphButton(
                        label: "DENY",
                        shortcut: keyHint(local: "esc", global: .denyPermission),
                        isFlashing: resolution == .deny
                    ) { resolve(.deny) }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("この tool 実行を拒否します")

                    GlyphButton(
                        label: "APPROVE",
                        shortcut: keyHint(local: "⏎", global: .approvePermission),
                        tint: DSColors.signalDone,
                        isProminent: true,
                        isFlashing: resolution == .approve
                    ) { resolve(.approve) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("\(permission.toolName) の実行を許可します")
                } else {
                    GlyphButton(
                        label: "DISMISS",
                        shortcut: controlActiveState == .key ? "⏎" : nil,
                        isProminent: true,
                        isFlashing: resolution == .dismiss
                    ) { resolve(.dismiss) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("この失効バナーを閉じます")
                }
            }
            .armedAfter()
        }
        // 面も amber に寄せる。押すまで agent が止まっているので、縁だけでなく面で気づきたい。
        .notchCard(accent: accent, tintsSurface: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(permission.canRespond
            ? "権限リクエスト: \(permission.toolName)"
            : "権限リクエストの応答期限切れ: \(permission.toolName)")
        // Approve/Deny の Return/Esc ショートカットはパネルが key window の間だけ効く
        // （NotchPanel は既定 canBecomeKey=false）。表示中だけ許可し、消えたら戻す（#2 と同様の経路）。
        .onAppear {
            NotificationCenter.default.post(name: .agentNotchSetKeyFocus, object: true)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .agentNotchSetKeyFocus, object: false)
        }
        // グローバルホットキーもここで受ける。**バナーが見えているときだけ効く**ので、
        // 画面に出ていない権限を承認してしまうことがない。
        .onReceive(NotificationCenter.default.publisher(for: .agentNotchHotKeyApprove)) { _ in
            guard permission.canRespond else { return }
            resolve(.approve)
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentNotchHotKeyDeny)) { _ in
            guard permission.canRespond else { return }
            resolve(.deny)
        }
    }

    /// 決定を確定する。**押した演出を見せてから**応答を送る。
    ///
    /// ホットキーで押した場合、応答が即座に飛ぶとバナーが「勝手に消えた」ように見えて
    /// 承認できたのかどうか分からない。どちらを押したのかを面の色で見せ、それが目に
    /// 入る間だけ待ってから送る。
    ///
    /// 二重送信は `resolution` で止める（連打・ホットキーとクリックの同時押し）。
    private func resolve(_ decision: Resolution) {
        guard resolution == nil else { return }
        resolution = decision
        Task {
            try? await Task.sleep(for: resolveDelay)
            switch decision {
            case .approve: onApprove()
            case .deny: onDeny()
            case .dismiss: onDismiss()
            }
        }
    }

    // MARK: - Headline

    /// mono 見出し + tool 名。状態グリフは置かない（パネル上部のグリフと二重になる）。
    private var headline: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(permission.canRespond ? "PERMISSION REQUIRED" : "RESPONSE WINDOW EXPIRED")
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.6)
                // 見出しも意味色にする。面・縁・見出しが同じ色を差すので、
                // 何が起きているのかを 1 色で言い切れる（失効時は赤に切り替わる）。
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            // tool 名は「何を」の補足なので、見出し（何が起きているか）より一段下げる。
            // ここも意味色にすると見出しと同じ階層に見えて、どちらを先に読むのか迷う。
            Text(permission.toolName.uppercased())
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(DSColors.inkDim)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(DSColors.lineDefault, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Tool input

    /// 何を許可するのかを等幅の素の情報として出す。`ToolLogRow` の出力ブロックと同じ見え方。
    ///
    /// Bash は `$ command` の形にする（ターミナルで打つのと同じ姿で確認できる方が、
    /// 何を許可したのか後から思い出せる）。
    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let command = permission.toolInput["command"], !command.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Text("$")
                        .foregroundStyle(DSColors.inkMute)
                    Text(command)
                        .foregroundStyle(DSColors.ink)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }

            ForEach(Array(otherInputs.prefix(3)), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 5) {
                    Text(key)
                        .foregroundStyle(DSColors.inkMute)
                    Text(String(value.prefix(120)))
                        .foregroundStyle(DSColors.ink.opacity(0.75))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(DSTypography.mono(s(10)))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // カードの中の面なので、黒ベタではなく material に暗幕を重ねて作る
        // （ベタ塗りだとカードの質感の中で 1 枚だけ板が浮く）。暗幕はカードより
        // わずかに濃いだけに留める——濃くすると material のブラーが潰れて、
        // 結局ベタ塗りと変わらなくなる。区別はこの差と細い枠で足りる。
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(DSColors.canvas.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DSColors.lineFaint, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// `command` は `$` 付きで、`description` はブロックの外に出しているので、残りだけ並べる。
    private var otherInputs: [(key: String, value: String)] {
        permission.toolInput
            .filter { $0.key != "command" && $0.key != "description" }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }
}

#Preview("Permission Banner") {
    PermissionBanner(
        permission: PermissionRequest(
            id: "1",
            agentType: .claudeCode,
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ["command": "rm -rf build/", "description": "Clean build artifacts"],
            toolUseId: "t1",
            timestamp: .now,
            canRespond: true
        ),
        onApprove: {},
        onDeny: {}
    )
    .padding(20)
    .frame(width: 460)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}

#Preview("Permission Banner (Expired)") {
    PermissionBanner(
        permission: PermissionRequest(
            id: "2",
            agentType: .claudeCode,
            sessionId: "s1",
            toolName: "Bash",
            toolInput: ["command": "rm -rf build/"],
            toolUseId: "t2",
            timestamp: .now,
            canRespond: false
        ),
        onApprove: {},
        onDeny: {},
        onDismiss: {}
    )
    .padding(20)
    .frame(width: 460)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
