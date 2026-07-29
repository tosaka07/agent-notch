import AgentNotchCore
import AppKit
import SwiftUI

/// Draws each agent's official logo **as a vector**.
///
/// # Why the SVG paths are embedded
/// Every placement is small — 10 to 12pt square — and a PNG falls apart at that size.
/// The logos are monochrome, so holding the path lets us draw them cleanly at any size and
/// swap the color, with no asset catalog or resource loading involved.
///
/// # Sources
/// - Claude: Anthropic brand assets (Claude symbol, official color #D97757)
/// - Codex: OpenAI brand assets (OpenAI Blossom, `OAI_OpenAI-Blossom_White.svg`)
///
/// Both are used to indicate a supported service, and are used unmodified
/// (no color inversion, no partial cropping).
enum AgentMarkPath {
    /// The Anthropic / Claude symbol. viewBox 0 0 125 125.
    static let claude = """
        M54.375 118.75L56.125 111L58.125 101L59.75 93L61.25 83.125L62.125 79.875L62 79.625L61.375
        79.75L53.875 90L42.5 105.375L33.5 114.875L31.375 115.75L27.625 113.875L28 110.375L30.125
        107.375L42.5 91.5L50 81.625L54.875 76L54.75 75.25H54.5L21.5 96.75L15.625 97.5L13 95.125L
        13.375 91.25L14.625 90L24.5 83.125L49.125 69.375L49.5 68.125L49.125 67.5H47.875L43.75 67.25L
        29.75 66.875L17.625 66.375L5.75 65.75L2.75 65.125L0 61.375L0.25 59.5L2.75 57.875L6.375
        58.125L14.25 58.75L26.125 59.5L34.75 60L47.5 61.375H49.5L49.75 60.5L49.125 60L48.625 59.5L
        36.25 51.25L23 42.5L16 37.375L12.25 34.75L10.375 32.375L9.625 27.125L13 23.375L17.625 23.75L
        18.75 24L23.375 27.625L33.25 35.25L46.25 44.875L48.125 46.375L49 45.875V45.5L48.125 44.125L
        41.125 31.375L33.625 18.375L30.25 13L29.375 9.75C29.0417 8.625 28.875 7.375 28.875 6L32.75
        0.750006L34.875 0L40.125 0.750006L42.25 2.625L45.5 10L50.625 21.625L58.75 37.375L61.125
        42.125L62.375 46.375L62.875 47.75H63.75V47L64.375 38L65.625 27.125L66.875 13.125L67.25 9.125
        L69.25 4.375L73.125 1.87501L76.125 3.25L78.625 6.875L78.25 9.125L76.875 18.75L73.875 33.875L
        72 44.125H73.125L74.375 42.75L79.5 36L88.125 25.25L91.875 21L96.375 16.25L99.25 14H104.625L
        108.5 19.875L106.75 26L101.25 33L96.625 38.875L90 47.75L86 54.875L86.375 55.375H87.25L
        102.125 52.125L110.25 50.75L119.75 49.125L124.125 51.125L124.625 53.125L122.875 57.375L
        112.625 59.875L100.625 62.25L82.75 66.5L82.5 66.625L82.75 67L90.75 67.75L94.25 68H102.75L
        118.5 69.125L122.625 71.875L125 75.125L124.625 77.75L118.25 80.875L109.75 78.875L89.75
        74.125L83 72.5H82V73L87.75 78.625L98.125 88L111.25 100.125L111.875 103.125L110.25 105.625L
        108.5 105.375L97 96.625L92.5 92.75L82.5 84.375H81.875V85.25L84.125 88.625L96.375 107L97
        112.625L96.125 114.375L92.875 115.5L89.5 114.875L82.25 104.875L74.875 93.5L68.875 83.375L
        68.25 83.875L64.625 121.625L63 123.5L59.25 125L56.125 122.625L54.375 118.75Z
        """

    /// OpenAI Blossom. viewBox 0 0 716 716 (the mark itself fits within 183–532, centered).
    static let openAI = """
        M508.749 317.399C516.777 287.314 508.991 253.884 485.389 230.282C461.788 206.681 428.36
        198.895 398.273 206.923C376.231 184.928 343.39 174.956 311.148 183.596C278.906 192.234
        255.45 217.292 247.36 247.361C217.291 255.451 192.233 278.91 183.595 311.149C174.957 343.391
        184.927 376.232 206.924 398.274C198.896 428.359 206.683 461.789 230.284 485.391C253.885
        508.992 287.313 516.779 317.401 508.75C339.442 530.745 372.286 540.717 404.525 532.079C
        436.767 523.441 460.223 498.384 468.313 468.315C498.383 460.224 523.44 436.766 532.078
        404.526C540.716 372.285 530.747 339.443 508.749 317.402V317.399ZM470.899 244.776C486.892
        260.77 493.488 282.601 490.687 303.412L415.577 260.046C412.411 258.218 408.509 258.218
        405.345 260.046L317.401 310.82V277.526C317.401 275.191 318.652 273.005 320.676 271.837L
        387.644 233.174C414.178 218.353 448.346 222.223 470.901 244.776H470.899ZM357.837 311.144L
        398.275 334.491V381.185L357.837 404.532L317.398 381.185V334.491L357.837 311.144ZM264.776
        269.693C265.207 239.305 285.644 211.649 316.453 203.393C338.3 197.54 360.505 202.744 377.127
        215.573L302.014 258.937C298.848 260.764 296.898 264.144 296.898 267.798V369.346L268.065
        352.699C266.043 351.531 264.776 349.353 264.776 347.017V269.691V269.693ZM203.391 316.454C
        209.244 294.608 224.854 277.978 244.276 269.999V356.73C244.276 360.384 246.226 363.763
        249.392 365.591L337.337 416.365L308.503 433.013C306.481 434.181 303.961 434.188 301.939
        433.02L234.971 394.357C208.868 378.789 195.138 347.261 203.391 316.454ZM244.775 470.9C
        228.781 454.906 222.186 433.075 224.986 412.264L300.096 455.63C303.263 457.457 307.164
        457.457 310.328 455.63L398.273 404.856V438.149C398.273 440.485 397.022 442.671 394.997
        443.839L328.029 482.502C301.495 497.322 267.327 493.452 244.772 470.9H244.775ZM450.897
        445.982C450.466 476.371 430.029 504.027 399.22 512.283C377.373 518.136 355.168 512.932
        338.547 500.102L413.659 456.738C416.826 454.911 418.775 451.532 418.775 447.877V346.329L
        447.609 362.977C449.631 364.145 450.897 366.323 450.897 368.659V445.985V445.982ZM512.282
        399.221C506.429 421.068 490.819 437.697 471.397 445.676V358.946C471.397 355.292 469.448
        351.912 466.281 350.085L378.336 299.311L407.17 282.663C409.192 281.495 411.712 281.487
        413.734 282.655L480.702 321.318C506.805 336.887 520.536 368.415 512.282 399.221Z
        """
}

/// A minimal parser turning an SVG `d` attribute into a `Path`.
///
/// The supported commands are only the ones the embedded logos use — `M` / `L` / `H` / `V` /
/// `C` / `Z` and their relative forms. This does not warrant pulling in a general SVG parser,
/// so **any command it cannot draw is silently ignored** (better to omit than to draw a broken logo).
struct SVGPathParser {
    static func path(from d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character?
        var numbers: [CGFloat] = []

        /// Consumes the accumulated numbers with the current command. Commands repeat (e.g. `L1 2 3 4`).
        func flush() {
            guard let command else {
                numbers.removeAll()
                return
            }
            let relative = command.isLowercase
            var index = 0
            func next() -> CGFloat? {
                guard index < numbers.count else { return nil }
                defer { index += 1 }
                return numbers[index]
            }

            switch Character(command.lowercased()) {
            case "m":
                while let x = next(), let y = next() {
                    let point = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    // Coordinate pairs after the first are treated as L (per the SVG spec).
                    if index == 2 {
                        path.move(to: point)
                        start = point
                    } else {
                        path.addLine(to: point)
                    }
                    current = point
                }
            case "l":
                while let x = next(), let y = next() {
                    let point = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    path.addLine(to: point)
                    current = point
                }
            case "h":
                while let x = next() {
                    let point = CGPoint(x: relative ? current.x + x : x, y: current.y)
                    path.addLine(to: point)
                    current = point
                }
            case "v":
                while let y = next() {
                    let point = CGPoint(x: current.x, y: relative ? current.y + y : y)
                    path.addLine(to: point)
                    current = point
                }
            case "c":
                while let x1 = next(), let y1 = next(), let x2 = next(), let y2 = next(),
                    let x = next(), let y = next()
                {
                    let origin = relative ? current : .zero
                    let control1 = CGPoint(x: origin.x + x1, y: origin.y + y1)
                    let control2 = CGPoint(x: origin.x + x2, y: origin.y + y2)
                    let point = CGPoint(x: origin.x + x, y: origin.y + y)
                    path.addCurve(to: point, control1: control1, control2: control2)
                    current = point
                }
            case "z":
                path.closeSubpath()
                current = start
            default:
                break
            }
            numbers.removeAll()
        }

        var number = ""
        func commitNumber() {
            guard !number.isEmpty, let value = Double(number) else {
                number = ""
                return
            }
            numbers.append(CGFloat(value))
            number = ""
        }

        for character in d {
            if character.isLetter {
                commitNumber()
                flush()
                command = character
                // Z takes no numbers, so settle it immediately.
                if character.lowercased() == "z" { flush() }
            } else if character == "-" && !number.isEmpty && !number.hasSuffix("e") {
                // A minus sign acting as a separator (`10-5` = 10, -5).
                commitNumber()
                number = "-"
            } else if character.isNumber || character == "." || character == "-" {
                number.append(character)
            } else {
                // Spaces, commas, and newlines are separators.
                commitNumber()
            }
        }
        commitNumber()
        flush()
        return path
    }
}

/// A `Shape` that fits an SVG path into `rect`.
///
/// Normalization uses the path's actual bounding box, so a logo with padding in its viewBox
/// (OpenAI Blossom's mark is the center 350 of a 716 square) still ends up optically the same
/// size as the others.
struct AgentMarkShape: Shape {
    let commands: String

    // The parse result is not cached: `Shape` conformance cannot cross actors, so there is no
    // place for a static mutable cache, and `Path` itself is not Sendable.
    // It is a ~400-token scan, so re-parsing per draw is fine for a handful of 10pt marks.
    func path(in rect: CGRect) -> Path {
        let raw = SVGPathParser.path(from: commands)
        let box = raw.boundingRect
        guard box.width > 0, box.height > 0 else { return Path() }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let transform = CGAffineTransform.identity
            .translatedBy(x: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        return raw.applying(transform)
    }
}

/// An agent's identifying mark. Placed leading of its formal label, or in a card's left column.
///
/// Colors follow each vendor's official color (Claude = #D97757 / OpenAI = monochrome).
/// This is a different axis from `AgentType.color` (the identification color used by gauges
/// and such) — don't conflate the two.
struct AgentMark: View {
    let agentType: AgentType
    var size: CGFloat = 10
    /// Set to paint the logo in the ground color instead (e.g. a recessed card). nil = official color.
    var color: Color?
    /// Font size of the **uppercase text** it sits next to.
    ///
    /// When set, the logo's center is aligned to the center of that font's cap height
    /// (use it inside an `HStack(alignment: .firstTextBaseline)`).
    /// A square logo floats high on baseline alignment, and sinks low on center alignment
    /// because uppercase text sits toward the top. Aligning to the text's **optical center**
    /// is what actually looks right.
    var alignedWithFontSize: CGFloat?

    var body: some View {
        mark
            .frame(width: size, height: size)
            .modifier(CapHeightAligned(markSize: size, fontSize: alignedWithFontSize))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        Group {
            if let commands = AgentMarkPath.commands(for: agentType) {
                AgentMarkShape(commands: commands)
                    .fill(color ?? AgentMarkPath.brandColor(for: agentType))
            } else {
                // Agents without a logo fall back to a single letter.
                Text(agentType.markLetter)
                    .font(DSTypography.mono(size * 0.8, weight: .semibold))
                    .foregroundStyle(color ?? DSColors.inkDim)
            }
        }
    }
}

/// Aligns the logo to the optical center of uppercase text.
///
/// Does nothing when `fontSize` is nil (so it drops straight into a center-aligned HStack).
private struct CapHeightAligned: ViewModifier {
    let markSize: CGFloat
    let fontSize: CGFloat?

    func body(content: Content) -> some View {
        if let fontSize {
            content.alignmentGuide(.firstTextBaseline) { dimensions in
                // The guide is the baseline's position in local coordinates.
                // We want the logo's center capHeight/2 above the baseline, so return the
                // center (height/2) plus that amount.
                dimensions.height / 2 + Self.capHeight(for: fontSize) / 2
            }
        } else {
            content
        }
    }

    /// SF Mono's cap height. Read from the actual font rather than hard-coding a ratio,
    /// so alignment holds when the text-size setting scales things.
    private nonisolated static func capHeight(for fontSize: CGFloat) -> CGFloat {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold).capHeight
    }
}

extension AgentMarkPath {
    static func commands(for agentType: AgentType) -> String? {
        switch agentType {
        case .claudeCode: claude
        case .codex: openAI
        case .geminiCLI, .custom: nil
        }
    }

    /// Official colors. OpenAI Blossom is specified as monochrome black/white, so use white on dark UI.
    static func brandColor(for agentType: AgentType) -> Color {
        switch agentType {
        case .claudeCode: Color(red: 0.851, green: 0.467, blue: 0.341)  // #D97757
        case .codex: DSColors.ink
        case .geminiCLI, .custom: DSColors.inkDim
        }
    }
}

extension AgentType {
    /// Fallback display for agents without a logo (a single letter).
    var markLetter: String {
        switch self {
        case .claudeCode: "C"
        case .codex: "X"
        case .geminiCLI: "G"
        case .custom: "?"
        }
    }
}

#Preview("Agent Marks") {
    VStack(alignment: .leading, spacing: 18) {
        ForEach([AgentType.claudeCode, .codex, .geminiCLI], id: \.self) { agent in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                AgentMark(agentType: agent, size: 10)
                AgentMark(agentType: agent, size: 14)
                AgentMark(agentType: agent, size: 24)
                AgentMark(agentType: agent, size: 24, color: DSColors.inkDim)
                // Example of aligning to a label's optical center (the real usage).
                AgentMark(agentType: agent, size: 9, alignedWithFontSize: 9)
                Text(agent.displayName.uppercased())
                    .font(DSTypography.mono(9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(DSColors.inkDim)
            }
        }
    }
    .padding(24)
    .background(Color(red: 0.078, green: 0.078, blue: 0.086))
}
