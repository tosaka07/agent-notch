import Defaults
import SwiftUI

struct SettingsView: View {
    @Default(.textSize) var textSize
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
        }
        .formStyle(.grouped)
        .frame(width: 300, height: 140)
    }
}
