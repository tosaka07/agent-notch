import AgentNotchCore
import Defaults
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

    private var scale: CGFloat { textSize.scale }
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    /// 応答できるかで意味色を切り替える。失効は「もう届かない」= エラー側の意味。
    private var accent: Color {
        permission.canRespond ? DSColors.signalAlert : DSColors.signalError
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            headline

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
                    GlyphButton(label: "DENY", shortcut: "esc") { onDeny() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("この tool 実行を拒否します")

                    GlyphButton(
                        label: "APPROVE",
                        shortcut: "⏎",
                        tint: DSColors.signalDone,
                        isProminent: true
                    ) { onApprove() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("\(permission.toolName) の実行を許可します")
                } else {
                    GlyphButton(label: "DISMISS", shortcut: "⏎", isProminent: true) { onDismiss() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("この失効バナーを閉じます")
                }
            }
            .armedAfter()
        }
        .notchCard(accent: accent)
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
    }

    // MARK: - Headline

    /// mono 見出し + tool 名。状態グリフは置かない（パネル上部のグリフと二重になる）。
    private var headline: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(permission.canRespond ? "PERMISSION REQUIRED" : "RESPONSE WINDOW EXPIRED")
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(DSColors.ink.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Text(permission.toolName.uppercased())
                .font(DSTypography.mono(s(9), weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(accent.opacity(0.4), lineWidth: 0.5)
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
                    Text("\(key)")
                        .foregroundStyle(DSColors.inkMute)
                    Text(String(value.prefix(120)))
                        .foregroundStyle(DSColors.ink.opacity(0.75))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(DSTypography.mono(s(11)))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.canvas)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DSColors.lineFaint, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// `command` は上で `$` 付きで出しているので、残りのキーだけを並べる。
    private var otherInputs: [(key: String, value: String)] {
        permission.toolInput
            .filter { $0.key != "command" }
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
