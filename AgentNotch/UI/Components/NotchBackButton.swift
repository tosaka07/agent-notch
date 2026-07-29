import SwiftUI

/// Back button placed in a full panel's physical-notch row.
///
/// Keeping the artwork and edge inset here makes navigation stay in the same
/// position across pages even when the content headers below have different
/// structures.
struct NotchBackButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DSColors.inkDim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .padding(.leading, 12)
    }
}
