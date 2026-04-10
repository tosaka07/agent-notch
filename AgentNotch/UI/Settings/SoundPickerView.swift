import Defaults
import SwiftUI

/// Picker for selecting a sound: none, system sound, or custom file.
struct SoundPickerView: View {
    let event: SoundEvent
    @Binding var choice: SoundChoice

    @State private var showFilePicker = false

    var body: some View {
        HStack {
            Label(event.label, systemImage: event.icon)

            Spacer()

            Menu {
                Button("なし") { choice = .none }

                Divider()

                ForEach(SoundChoice.systemSounds, id: \.self) { name in
                    Button(name) {
                        choice = .system(name)
                        SoundPlayer.preview(choice)
                    }
                }

                Divider()

                Button("カスタム音声ファイル...") {
                    showFilePicker = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(choice.displayName)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                SoundPlayer.preview(choice)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(choice.kind == .none)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                choice = .custom(url.path)
                SoundPlayer.preview(choice)
            }
        }
    }
}
