import KitfoldCore
import SwiftUI

// Each agent's own mark, drawn from SVG path data so it stays crisp at any size and the app
// needs no resource bundle. Logos are trademarks of their owners, used here only to identify the agents.
//
// Sources:
// - Claude Code: the Claude spark, lobe-icons `claude-color` (MIT, github.com/lobehub/lobe-icons).
// - Codex: the Codex mark, lobe-icons `codex` / `codex-color`, painted like the Codex app icon
//   (blue-violet gradient, white prompt).
// - OpenCode: github.com/anomalyco/opencode (MIT), `packages/console/app/src/asset/brand/opencode-logo-{light,dark}-square.svg`.
// - Gemini CLI: lobe-icons `geminicli-color`, a vector of the icon geminicli.com ships.
//
// The view boxes below are padded so the four marks carry similar visual weight side by side.

/// The agent's own mark, or nil for agents without one (callers fall back to the monogram).
///
/// Fills the frame it is given; the mark is scaled to fit, keeping its aspect ratio, and centred.
/// Monochrome parts follow the colour scheme; colour marks keep their brand colours.
struct AgentLogo: View {
    let mark: Mark
    @Environment(\.colorScheme) private var colorScheme

    init?(_ id: AgentID) {
        guard let mark = Mark.byAgent[id] else { return nil }
        self.mark = mark
    }

    init(mark: Mark) {
        self.mark = mark
    }

    var body: some View {
        let mark = mark
        let dark = colorScheme == .dark
        Canvas { context, size in
            mark.draw(in: &context, size: size, dark: dark)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(L("\(mark.name) logo")))
        .accessibilityAddTraits(.isImage)
    }
}

extension AgentLogo {
    /// A logo: a square view box (padding included) and its paint layers, back to front.
    struct Mark {
        /// The agent's name; the accessibility label is "<name> logo".
        let name: String
        let viewBox: CGRect
        let layers: [Layer]

        func draw(in context: inout GraphicsContext, size: CGSize, dark: Bool) {
            let scale = min(size.width / viewBox.width, size.height / viewBox.height)
            guard scale > 0, scale.isFinite else { return }
            let transform = CGAffineTransform(
                translationX: (size.width - viewBox.width * scale) / 2 - viewBox.minX * scale,
                y: (size.height - viewBox.height * scale) / 2 - viewBox.minY * scale
            ).scaledBy(x: scale, y: scale)
            for layer in layers {
                context.fill(
                    layer.path.applying(transform), with: layer.paint.shading(dark: dark, transform: transform),
                    style: FillStyle(eoFill: layer.evenOdd))
            }
        }
    }

    struct Layer {
        let path: Path
        let paint: Paint
        let evenOdd: Bool

        /// `d` is SVG path data in the mark's view-box coordinates.
        init(_ d: String, _ paint: Paint, evenOdd: Bool = false) {
            self.path = SVGPathData.path(d)
            self.paint = paint
            self.evenOdd = evenOdd
        }
    }

    enum Paint {
        case solid(UInt32)
        /// Monochrome parts: one colour for light appearance, one for dark.
        case adaptive(light: UInt32, dark: UInt32)
        /// SVG `linearGradient` with `gradientUnits="userSpaceOnUse"` (points in view-box coordinates).
        case linear(from: CGPoint, to: CGPoint, stops: [Stop])

        struct Stop {
            let rgb: UInt32
            var opacity = 1.0
            let location: Double
        }

        func shading(dark: Bool, transform: CGAffineTransform) -> GraphicsContext.Shading {
            switch self {
            case .solid(let rgb):
                return .color(Self.color(rgb))
            case .adaptive(let light, let darkRGB):
                return .color(Self.color(dark ? darkRGB : light))
            case .linear(let from, let to, let stops):
                let gradient = Gradient(stops: stops.map { .init(color: Self.color($0.rgb, $0.opacity), location: $0.location) })
                return .linearGradient(gradient, startPoint: from.applying(transform), endPoint: to.applying(transform))
            }
        }

        static func color(_ rgb: UInt32, _ opacity: Double = 1) -> Color {
            Color(
                .sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255, opacity: opacity)
        }
    }
}

// MARK: - The marks

extension AgentLogo.Mark {
    static let byAgent: [AgentID: AgentLogo.Mark] = [
        .claudeCode: .claude,
        .codex: .codex,
        .openCode: .openCode,
        .geminiCLI: .geminiCLI,
    ]

    /// Anthropic's Claude spark in Claude terracotta.
    static let claude = AgentLogo.Mark(
        name: "Claude Code", viewBox: CGRect(x: 0, y: 0, width: 24, height: 24),
        layers: [
            .init(
                "M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352"
                    + ".48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688"
                    + "-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103"
                    + ".019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134"
                    + ".42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376"
                    + "-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82"
                    + ".85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606"
                    + " 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036"
                    + "h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81"
                    + " 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17"
                    + ".353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747"
                    + ".322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37"
                    + ".067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243"
                    + " 1.908-1.312-.006.006z",
                .solid(0xD97757))
        ])

    /// OpenAI Codex: the cloud-shaped mark with a `>_` prompt, painted like the Codex app icon.
    static let codex = AgentLogo.Mark(
        name: "Codex", viewBox: CGRect(x: -0.75, y: -0.75, width: 25.5, height: 25.5),
        layers: [
            .init(
                "M8.086.457a6.105 6.105 0 013.046-.415c1.333.153 2.521.72 3.564 1.7a.117.117 0 00.107.029c1.408-.346 2.762-.224 4.061"
                    + ".366l.063.03.154.076c1.357.703 2.33 1.77 2.918 3.198.278.679.418 1.388.421 2.126a5.655 5.655 0 01-.18 1.631.167.167"
                    + " 0 00.04.155 5.982 5.982 0 011.578 2.891c.385 1.901-.01 3.615-1.183 5.14l-.182.22a6.063 6.063 0 01-2.934 1.851.162"
                    + ".162 0 00-.108.102c-.255.736-.511 1.364-.987 1.992-1.199 1.582-2.962 2.462-4.948 2.451-1.583-.008-2.986-.587-4.21"
                    + "-1.736a.145.145 0 00-.14-.032c-.518.167-1.04.191-1.604.185a5.924 5.924 0 01-2.595-.622 6.058 6.058 0 01-2.146-1.781"
                    + "c-.203-.269-.404-.522-.551-.821a7.74 7.74 0 01-.495-1.283 6.11 6.11 0 01-.017-3.064.166.166 0 00.008-.074.115.115 0"
                    + " 00-.037-.064 5.958 5.958 0 01-1.38-2.202 5.196 5.196 0 01-.333-1.589 6.915 6.915 0 01.188-2.132c.45-1.484 1.309"
                    + "-2.648 2.577-3.493.282-.188.55-.334.802-.438.286-.12.573-.22.861-.304a.129.129 0 00.087-.087A6.016 6.016 0 015.635"
                    + " 2.31C6.315 1.464 7.132.846 8.086.457z",
                .linear(
                    from: CGPoint(x: 12, y: 0), to: CGPoint(x: 12, y: 24),
                    stops: [.init(rgb: 0xB1A7FF, location: 0), .init(rgb: 0x7A9DFF, location: 0.5), .init(rgb: 0x3941FF, location: 1)])),
            .init(
                "M7.282 8.307a.848.848 0 00-1.473.842l1.694 2.965-1.688 2.848a.849.849 0 001.46.864l1.94-3.272a.849.849 0 00.007-.854"
                    + "l-1.94-3.393zM12.728 14.547a.849.849 0 000 1.695h4.848a.849.849 0 000-1.696h-4.848z",
                .solid(0xFFFFFF)),
        ])

    /// opencode's pixel "O": dark on light backgrounds, light on dark ones (the project's own two variants).
    static let openCode = AgentLogo.Mark(
        name: "OpenCode", viewBox: CGRect(x: -45, y: -15, width: 330, height: 330),
        layers: [
            .init("M180 240H60V120H180V240Z", .adaptive(light: 0xCFCECD, dark: 0x4B4646)),
            .init("M180 60H60V240H180V60ZM240 300H0V0H240V300Z", .adaptive(light: 0x211E1E, dark: 0xF1ECEC), evenOdd: true),
        ])

    /// Gemini CLI's own mark: a `>` prompt on a dark tile with a Google gradient rim.
    static let geminiCLI = AgentLogo.Mark(
        name: "Gemini CLI", viewBox: CGRect(x: -1.25, y: -1.25, width: 26.5, height: 26.5),
        layers: [
            .init(
                "M0 4.391A4.391 4.391 0 014.391 0h15.217A4.391 4.391 0 0124 4.391v15.217A4.391 4.391 0 0119.608 24H4.391A4.391 4.391 0"
                    + " 010 19.608V4.391z",
                .linear(
                    from: CGPoint(x: 24, y: 6.587), to: CGPoint(x: 0, y: 16.494),
                    stops: [
                        .init(rgb: 0xEE4D5D, location: 0), .init(rgb: 0xB381DD, location: 0.328),
                        .init(rgb: 0x207CFE, location: 0.476),
                    ])),
            .init(
                "M19.74 1.444a2.816 2.816 0 012.816 2.816v15.48a2.816 2.816 0 01-2.816 2.816H4.26a2.816 2.816 0 01-2.816-2.816V4.26"
                    + "A2.816 2.816 0 014.26 1.444h15.48zM7.236 8.564l7.752 3.728-7.752 3.727v2.802l9.557-4.596v-3.866L7.236 5.763v2.801z",
                .solid(0x1E1E2E), evenOdd: true),
        ])
}

// MARK: - SVG path data

/// Builds a `Path` from SVG path data: M L H V C S Q T A Z, absolute and relative, including the compact
/// syntax icon exporters emit ("1.5.5", "-.2", arc flags without separators such as "01-.1-.7").
private enum SVGPathData {
    static func path(_ d: String) -> Path {
        var scanner = Scanner(bytes: Array(d.utf8))
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: UInt8 = 0

        while let next = scanner.peek() {
            if Scanner.isCommand(next) {
                command = next
                scanner.index += 1
            } else if command == 0 || command == UInt8(ascii: "Z") || command == UInt8(ascii: "z") {
                break  // numbers with no command to repeat: malformed
            }
            let relative = command >= UInt8(ascii: "a")
            let origin = relative ? current : .zero
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return CGPoint(x: origin.x + x, y: origin.y + y)
            }
            var cubicControl: CGPoint?
            var quadControl: CGPoint?

            switch command | 0x20 {  // lower-cased
            case UInt8(ascii: "m"):
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")  // further pairs are line-tos
            case UInt8(ascii: "l"):
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case UInt8(ascii: "h"):
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: origin.x + x, y: current.y)
                path.addLine(to: current)
            case UInt8(ascii: "v"):
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: origin.y + y)
                path.addLine(to: current)
            case UInt8(ascii: "c"):
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                cubicControl = c2
                current = p
            case UInt8(ascii: "s"):
                guard let c2 = point(), let p = point() else { return path }
                let c1 = lastCubicControl.map { reflect($0, about: current) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                cubicControl = c2
                current = p
            case UInt8(ascii: "q"):
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                quadControl = c
                current = p
            case UInt8(ascii: "t"):
                guard let p = point() else { return path }
                let c = lastQuadControl.map { reflect($0, about: current) } ?? current
                path.addQuadCurve(to: p, control: c)
                quadControl = c
                current = p
            case UInt8(ascii: "a"):
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                    let largeArc = scanner.flag(), let sweep = scanner.flag(), let p = point()
                else { return path }
                addArc(&path, from: current, to: p, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep)
                current = p
            case UInt8(ascii: "z"):
                path.closeSubpath()
                current = subpathStart
            default:
                return path  // unknown command
            }
            lastCubicControl = cubicControl
            lastQuadControl = quadControl
        }
        return path
    }

    private static func reflect(_ p: CGPoint, about c: CGPoint) -> CGPoint {
        CGPoint(x: 2 * c.x - p.x, y: 2 * c.y - p.y)
    }

    /// Elliptical arc as cubic Béziers (SVG 1.1 implementation notes, F.6.5 / F.6.6), one per quarter turn at most.
    private static func addArc(
        _ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, largeArc: Bool,
        sweep: Bool
    ) {
        guard p0 != p1 else { return }
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0 else { return path.addLine(to: p1) }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let hx = (p0.x - p1.x) / 2
        let hy = (p0.y - p1.y) / 2
        let x1 = cosPhi * hx + sinPhi * hy
        let y1 = -sinPhi * hx + cosPhi * hy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var k = denominator > 0 ? max(0, numerator / denominator).squareRoot() : 0
        if largeArc == sweep { k = -k }
        let cxp = k * rx * y1 / ry
        let cyp = -k * ry * x1 / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let ux = (x1 - cxp) / rx
        let uy = (y1 - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * x * cosPhi - ry * y * sinPhi, y: cy + rx * x * sinPhi + ry * y * cosPhi)
        }
        let segments = max(1, Int((abs(delta) / (.pi / 2) - 1e-6).rounded(.up)))
        let step = delta / CGFloat(segments)
        let t = 4 / 3 * tan(step / 4)
        var theta = theta1
        for i in 0..<segments {
            let (c1, s1) = (cos(theta), sin(theta))
            let (c2, s2) = (cos(theta + step), sin(theta + step))
            let end = i == segments - 1 ? p1 : map(c2, s2)
            path.addCurve(to: end, control1: map(c1 - t * s1, s1 + t * c1), control2: map(c2 + t * s2, s2 - t * c2))
            theta += step
        }
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        static func isCommand(_ b: UInt8) -> Bool {
            switch b | 0x20 {
            case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "v"), UInt8(ascii: "c"), UInt8(ascii: "s"),
                UInt8(ascii: "q"), UInt8(ascii: "t"), UInt8(ascii: "a"), UInt8(ascii: "z"):
                return true
            default:
                return false
            }
        }

        private static func isDigit(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") }

        mutating func skipSeparators() {
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: " "), UInt8(ascii: ","), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"): index += 1
                default: return
                }
            }
        }

        mutating func peek() -> UInt8? {
            skipSeparators()
            return index < bytes.count ? bytes[index] : nil
        }

        /// A single-character arc flag ("0" or "1"); flags need no separator after them.
        mutating func flag() -> Bool? {
            guard let b = peek(), b == UInt8(ascii: "0") || b == UInt8(ascii: "1") else { return nil }
            index += 1
            return b == UInt8(ascii: "1")
        }

        /// A number; a second "." or a sign starts the next one.
        mutating func number() -> CGFloat? {
            skipSeparators()
            let start = index
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
            var digits = false
            var dot = false
            while index < bytes.count {
                let b = bytes[index]
                if Self.isDigit(b) {
                    digits = true
                } else if b == UInt8(ascii: "."), !dot {
                    dot = true
                } else {
                    break
                }
                index += 1
            }
            if digits, index < bytes.count, bytes[index] | 0x20 == UInt8(ascii: "e") {
                var j = index + 1
                if j < bytes.count, bytes[j] == UInt8(ascii: "-") || bytes[j] == UInt8(ascii: "+") { j += 1 }
                if j < bytes.count, Self.isDigit(bytes[j]) {
                    index = j
                    while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
                }
            }
            guard digits, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                index = start
                return nil
            }
            return CGFloat(value)
        }
    }
}
