import Defaults
import SwiftUI

struct SettingsView: View {
    @Default(.textSize) var textSize
    @Default(.sessionTimeout) var sessionTimeout
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
            }

            Section("セッション") {
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
        .frame(width: 320, height: 260)
    }
}
