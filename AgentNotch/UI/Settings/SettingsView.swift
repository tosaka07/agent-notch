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
                Button("デフォルトに戻す") {
                    KeyboardShortcuts.reset(.jumpToNotification, .jumpToTerminal)
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
        .frame(width: 360, height: soundEnabled ? 700 : 600)
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
