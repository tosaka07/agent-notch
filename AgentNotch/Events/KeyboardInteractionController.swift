import AgentNotchCore
import AppKit
import Combine
import Observation

/// The interaction layer currently visible in one notch panel.
///
/// Keeping this separate from `NotchMode` lets an interruption take precedence
/// over the session-detail page that contains it.
enum KeyboardInteractionContext: Equatable, Sendable {
    case compact
    case notification
    case expanded
    case sessionDetail
    case permission
    case question
    case usage
}

/// Semantic commands emitted by keyboard input.
///
/// Views respond to commands instead of decoding `NSEvent` independently. This
/// keeps shortcut precedence and key consumption in one place.
enum KeyboardCommand: Equatable, Sendable {
    case focusInitial
    case movePrevious
    case moveNext
    case activate
    case cancel
    case back
    case closePanel
    case jumpToSessionDestination
    case jumpToTerminal
    case approve
    case deny
    /// Control is held (`true`) or released (`false`). Session detail reveals
    /// every tool's contents for as long as it is held.
    case peekTools(Bool)
    case refresh
    case toggleSelection
    case previousQuestion
    case nextQuestion
    case togglePreview
    case selectNumber(Int)
}

struct KeyboardCommandEvent: Equatable, Sendable {
    let id = UUID()
    let command: KeyboardCommand
}

/// Framework-independent representation used by the shortcut resolver and its
/// tests.
struct KeyStroke: Equatable, Sendable {
    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: UInt8

        static let control = Self(rawValue: 1 << 0)
        static let option = Self(rawValue: 1 << 1)
        static let shift = Self(rawValue: 1 << 2)
        static let command = Self(rawValue: 1 << 3)
    }

    let keyCode: UInt16
    let characters: String
    let modifiers: Modifiers
}

enum KeyboardShortcutResolver {
    static func command(
        for stroke: KeyStroke,
        in context: KeyboardInteractionContext
    ) -> KeyboardCommand? {
        let characters = stroke.characters.lowercased()
        let modifiers = stroke.modifiers

        if modifiers == [.control] {
            switch (context, characters) {
            case (.notification, "p"), (.expanded, "p"), (.question, "p"):
                return .movePrevious
            case (.notification, "n"), (.expanded, "n"), (.question, "n"):
                return .moveNext
            case (.question, "b"):
                return .previousQuestion
            case (.question, "f"):
                return .nextQuestion
            default:
                return nil
            }
        }

        if modifiers == [.command], context == .usage, characters == "r" {
            return .refresh
        }

        // Modified keys that are not explicitly registered remain available to
        // the app or the current text editor.
        guard modifiers.isEmpty else { return nil }

        switch context {
        case .notification, .expanded:
            switch stroke.keyCode {
            case 0x7E: return .movePrevious  // ↑
            case 0x7D: return .moveNext  // ↓
            case 0x24, 0x4C: return .activate  // Return / keypad Enter
            case 0x35: return .closePanel  // Escape
            default:
                if characters == "k" { return .movePrevious }
                if characters == "j" { return .moveNext }
                if context == .expanded, characters == "t" { return .jumpToSessionDestination }
                return nil
            }

        case .sessionDetail:
            if characters == "t" { return .jumpToSessionDestination }
            return stroke.keyCode == 0x35 ? .back : nil

        case .permission:
            switch stroke.keyCode {
            case 0x24, 0x4C: return .activate
            case 0x35: return .cancel
            default: return nil
            }

        case .question:
            switch stroke.keyCode {
            case 0x7E: return .movePrevious
            case 0x7D: return .moveNext
            case 0x7B: return .previousQuestion
            case 0x7C: return .nextQuestion
            case 0x31: return .toggleSelection
            case 0x24, 0x4C: return .activate
            case 0x35: return .closePanel
            default:
                if characters == "p" { return .togglePreview }
                if let number = Int(characters), (1...9).contains(number) {
                    return .selectNumber(number)
                }
                return nil
            }

        case .usage:
            return stroke.keyCode == 0x35 ? .back : nil

        case .compact:
            return stroke.keyCode == 0x35 ? .closePanel : nil
        }
    }
}

/// Owns keyboard engagement for exactly one notch panel.
///
/// Passive panels never install a local key monitor and never become key.
/// Explicit user interaction (`engage`) enables the panel, installs the single
/// local monitor, and publishes semantic commands to the visible SwiftUI page.
@MainActor
@Observable
final class KeyboardInteractionController {
    private(set) var isEngaged = false
    private(set) var context: KeyboardInteractionContext = .compact

    @ObservationIgnored
    let commands = PassthroughSubject<KeyboardCommandEvent, Never>()

    @ObservationIgnored
    private weak var panel: NotchPanel?

    @ObservationIgnored
    private var keyMonitor: Any?

    /// Last published Control state. `flagsChanged` fires for every modifier, so
    /// the transition is derived here instead of republishing on each event.
    @ObservationIgnored
    private var isControlHeld = false

    /// Called immediately before this panel engages. The display coordinator
    /// uses it to disengage every other panel first.
    @ObservationIgnored
    var onWillEngage: (() -> Void)?

    func attach(to panel: NotchPanel) {
        self.panel = panel
    }

    func detach() {
        disengage()
        onWillEngage = nil
        panel = nil
    }

    func updateContext(_ context: KeyboardInteractionContext) {
        guard self.context != context else { return }
        self.context = context
        if isEngaged {
            emit(.focusInitial)
        }
    }

    func engage() {
        onWillEngage?()
        if isEngaged {
            panel?.allowKeyFocus = true
            panel?.makeKey()
            return
        }
        isEngaged = true
        installKeyMonitor()
        panel?.allowKeyFocus = true
        panel?.makeKey()
        emit(.focusInitial)
        Log.input.info("Keyboard engagement ON context=\(String(describing: context))")
    }

    func disengage() {
        guard isEngaged || keyMonitor != nil || panel?.allowKeyFocus == true else { return }
        // A peek held at the moment focus leaves would never see its key-up, so
        // end it here rather than leaving the log stuck open.
        setControlHeld(false)
        isEngaged = false
        removeKeyMonitor()
        panel?.resignKey()
        panel?.allowKeyFocus = false
        Log.input.info("Keyboard engagement OFF")
    }

    func handleGlobal(_ action: GlobalHotKeyAction) {
        switch action {
        case .focusPanel:
            if isEngaged {
                disengage()
                emit(.closePanel)
            } else {
                engage()
            }
        case .jumpToTerminal:
            emit(.jumpToTerminal)
        case .approvePermission:
            emit(.approve)
        case .denyPermission:
            emit(.deny)
        }
    }

    private func setControlHeld(_ held: Bool) {
        guard isControlHeld != held else { return }
        isControlHeld = held
        emit(.peekTools(held))
    }

    private func emit(_ command: KeyboardCommand) {
        commands.send(KeyboardCommandEvent(command: command))
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard isEngaged, panel?.isKeyWindow == true else {
            setControlHeld(false)
            return event
        }

        // Holding Control is a peek, not a shortcut: it is never consumed, so
        // chorded shortcuts such as ⌃N keep working while it is down.
        if event.type == .flagsChanged {
            setControlHeld(
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
            )
            return event
        }

        // Let a TextField's field editor own typing and Return. QuestionBanner's
        // onSubmit handles the latter without the router firing a second action.
        if let editor = panel?.firstResponder as? NSTextView, editor.isEditable {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: KeyStroke.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        let stroke = KeyStroke(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers ?? "",
            modifiers: modifiers
        )
        guard let command = KeyboardShortcutResolver.command(for: stroke, in: context)
        else { return event }

        emit(command)
        return nil
    }
}
