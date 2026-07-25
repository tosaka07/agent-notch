import AgentNotchCore
import Defaults
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Default(.textSize) var textSize
    @Default(.sessionTimeout) var sessionTimeout
    @Default(.notificationTapAction) var notificationTapAction
    @Default(.displayMode) var displayMode
    @Default(.specificDisplayUUID) var specificDisplayUUID
    @Default(.soundEnabled) var soundEnabled
    @Default(.soundCompleted) var soundCompleted
    @Default(.soundSubagentCompleted) var soundSubagentCompleted
    @Default(.soundPermission) var soundPermission
    @Default(.soundError) var soundError
    @Default(.cardPromptSource) var cardPromptSource
    @Default(.usageEnabled) var usageEnabled
    @Default(.usageGaugeStyle) var usageGaugeStyle
    @Default(.usageGaugeMetric) var usageGaugeMetric
    @Default(.panelSurfaceStyle) var panelSurfaceStyle
    var onClose: (() -> Void)? = nil

    var body: some View {
        Form {
            Section("表示") {
                Picker("文字サイズ", selection: $textSize) {
                    ForEach(TextSizePreference.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("プレビュー:")
                        .foregroundStyle(.secondary)
                    Text("Aa テスト Preview 123")
                        .font(.system(size: 11 * textSize.scale))
                }

                Picker("パネルの背景", selection: $panelSurfaceStyle) {
                    ForEach(PanelSurfaceStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text("「ガラス」は展開パネルの上端を黒のまま残し、下端に向かって背景が透けます。\n上端は物理 notch と地続きにするため常に不透明です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("ディスプレイ", selection: $displayMode) {
                    ForEach(DisplayModePreference.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if displayMode == .specificDisplay {
                    Picker("対象ディスプレイ", selection: $specificDisplayUUID) {
                        ForEach(availableDisplays, id: \.uuid) { display in
                            HStack(spacing: 6) {
                                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                                    .font(.system(size: 10))
                                Text(display.name)
                            }
                            .tag(display.uuid)
                        }
                    }
                }
            }

            Section("通知") {
                Picker("タップ時の動作", selection: $notificationTapAction) {
                    ForEach(NotificationTapAction.allCases, id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }
            }

            Section("ショートカット") {
                KeyboardShortcuts.Recorder("通知にジャンプ", name: .jumpToNotification)
                KeyboardShortcuts.Recorder("ターミナルにジャンプ", name: .jumpToTerminal)
                KeyboardShortcuts.Recorder("権限を承認", name: .approvePermission)
                KeyboardShortcuts.Recorder("権限を拒否", name: .denyPermission)
                Text("承認・拒否はアプリが非アクティブでも効きます。\nnotch のパネルはクリックするまでキーボード入力を受け取れないため、\nバナーの ⏎ / esc はパネルをクリックしたあとだけ有効です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("デフォルトに戻す") {
                    KeyboardShortcuts.reset(
                        .jumpToNotification, .jumpToTerminal, .approvePermission, .denyPermission
                    )
                }
                .font(.caption)
            }

            Section("サウンド") {
                Toggle("サウンドを有効にする", isOn: $soundEnabled)

                if soundEnabled {
                    SoundPickerView(event: .sessionCompleted, choice: $soundCompleted)
                    SoundPickerView(event: .subagentCompleted, choice: $soundSubagentCompleted)
                    SoundPickerView(event: .permissionWaiting, choice: $soundPermission)
                    SoundPickerView(event: .error, choice: $soundError)
                }
            }

            Section("使用量") {
                Toggle("使用量を表示する", isOn: $usageEnabled)
                Text("Claude / Codex のレート制限の消費状況を一覧のトップバー左側に出します。\nゲージをクリックすると全内訳を表示します。\nOFF にすると資格情報の読み取りも API 呼び出しも行いません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if usageEnabled {
                    Picker("ゲージの表示", selection: $usageGaugeStyle) {
                        ForEach(UsageGaugeStyle.allCases, id: \.self) { style in
                            Text(style.label).tag(style)
                        }
                    }

                    Picker("ゲージに出す枠", selection: $usageGaugeMetric) {
                        ForEach(UsageGaugeMetric.allCases, id: \.self) { metric in
                            Text(metric.label).tag(metric)
                        }
                    }
                    Text("エージェントごとに 1 つだけ表示します。\n選んだ枠が無いエージェント（Codex にはモデル別枠が無い等）は自動になります。\n全内訳は使用量ページで確認できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("セッション") {
                Picker("プロンプト表示", selection: $cardPromptSource) {
                    ForEach(CardPromptSource.allCases, id: \.self) { source in
                        Text(source.label).tag(source)
                    }
                }

                Picker("自動削除", selection: $sessionTimeout) {
                    ForEach(SessionTimeoutPreference.allCases, id: \.self) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                Text("最後の活動から指定時間経過した非稼働セッションを自動削除します。\nディレクトリが削除された場合は即座に削除されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: soundEnabled ? 880 : 780)
        .onAppear {
            // Auto-select first display if none set
            if displayMode == .specificDisplay, specificDisplayUUID.isEmpty,
               let first = availableDisplays.first {
                specificDisplayUUID = first.uuid
            }
        }
    }

    private struct DisplayInfo: Identifiable {
        let uuid: String
        let name: String
        let isBuiltin: Bool
        var id: String { uuid }
    }

    private var availableDisplays: [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            return DisplayInfo(
                uuid: uuid,
                name: screen.displayName,
                isBuiltin: screen.isBuiltinDisplay
            )
        }
    }
}
