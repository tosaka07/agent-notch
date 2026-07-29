import Defaults
import SwiftUI

/// A typed keyboard chord used by both buttons and navigation legends.
///
/// Callers choose semantic keys instead of passing display strings such as
/// "⌥⇧⏎". `fromDisplayDescription` exists only for user-configurable global
/// shortcuts supplied by KeyboardShortcuts.
struct ShortcutChord: Equatable, Sendable {
    enum Key: Equatable, Sendable {
        case control
        case option
        case shift
        case command
        case escape
        case returnKey
        case delete
        case space
        case up
        case down
        case left
        case right
        case character(String)

        var label: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            case .escape: "esc"
            case .returnKey: "↩"
            case .delete: "⌫"
            case .space: "space"
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            case .character(let value): value
            }
        }
    }

    let keys: [Key]

    static let escape = Self(keys: [.escape])
    static let returnKey = Self(keys: [.returnKey])
    static let delete = Self(keys: [.delete])
    static let space = Self(keys: [.space])
    static let up = Self(keys: [.up])
    static let down = Self(keys: [.down])
    static let left = Self(keys: [.left])
    static let right = Self(keys: [.right])
    static let verticalArrows = Self(keys: [.up, .down])
    static let horizontalArrows = Self(keys: [.left, .right])
    static let controlKey = Self(keys: [.control])
    static let commandR = Self(keys: [.command, .character("R")])

    static func character(_ value: String) -> Self {
        Self(keys: [.character(value.uppercased())])
    }

    static func fromDisplayDescription(_ value: String) -> Self? {
        guard !value.isEmpty else { return nil }
        let lowered = value.lowercased()
        if lowered == "esc" || lowered == "escape" { return .escape }
        if lowered == "space" { return .space }

        var keys: [Key] = []
        var literal = ""

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            keys.append(.character(literal.uppercased()))
            literal = ""
        }

        for character in value {
            let key: Key? =
                switch character {
                case "⌃": .control
                case "⌥": .option
                case "⇧": .shift
                case "⌘": .command
                case "↩", "⏎", "\r", "\n": .returnKey
                case "⌫", "⌦": .delete
                case "↑": .up
                case "↓": .down
                case "←": .left
                case "→": .right
                default: nil
                }
            if let key {
                flushLiteral()
                keys.append(key)
            } else if !character.isWhitespace {
                literal.append(character)
            }
        }
        flushLiteral()
        return keys.isEmpty ? nil : Self(keys: keys)
    }
}

/// A keycap-style hint. Every physical key gets its own bordered cap, including
/// Return, so local and modifier-heavy global shortcuts share one grammar.
struct KeyHint: View {
    let chord: ShortcutChord
    var isEnabled = true

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(chord.keys.enumerated()), id: \.offset) { _, key in
                Text(key.label)
                    .font(DSTypography.mono(s(9), weight: .semibold))
                    .foregroundStyle(isEnabled ? DSColors.inkDim : DSColors.inkMute)
                    .padding(.horizontal, 5)
                    .frame(minWidth: s(18), minHeight: s(18))
                    .background(DSColors.ink.opacity(isEnabled ? 0.04 : 0.015))
                    .overlay(
                        DSShape.rounded(5)
                            .stroke(
                                isEnabled ? DSColors.lineStrong : DSColors.lineFaint,
                                lineWidth: 0.75
                            )
                    )
                    .clipShape(DSShape.rounded(5))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L("Keyboard shortcut: \(chord.keys.map(\.label).joined(separator: " "))")
        )
    }
}

/// Compact legend used for collection navigation hints.
struct KeyHintLabel: View {
    let chord: ShortcutChord
    let label: String

    @Default(.textSize) private var textSize
    private func s(_ base: CGFloat) -> CGFloat { textSize.scaled(base) }

    var body: some View {
        HStack(spacing: 4) {
            KeyHint(chord: chord)
            Text(label)
                .font(DSTypography.mono(s(8), weight: .medium))
                .tracking(0.5)
                .foregroundStyle(DSColors.inkMute)
        }
        .fixedSize()
    }
}
