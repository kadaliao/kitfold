// Composes a release-style screenshot: gradient backdrop, headline, and the app window
// (optionally with a sheet on top), rounded and shadowed.
//
//   swift scripts/screenshots/frame.swift --in window.png [--overlay sheet.png] --out out.png \
//       --title "…" --subtitle "…" [--theme dark|light]
import AppKit

var opts: [String: String] = [:]
var it = CommandLine.arguments.dropFirst().makeIterator()
while let k = it.next() { if k.hasPrefix("--"), let v = it.next() { opts[String(k.dropFirst(2))] = v } }
guard let input = opts["in"], let output = opts["out"], let window = NSImage(contentsOfFile: input) else {
    FileHandle.standardError.write(Data("usage: frame.swift --in <png> --out <png> --title <t> --subtitle <s>\n".utf8))
    exit(2)
}
let overlay = opts["overlay"].flatMap(NSImage.init(contentsOfFile:))
let dark = (opts["theme"] ?? "dark") == "dark"

let W = 3200, H = 2000
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let canvas = CGRect(x: 0, y: 0, width: W, height: H)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

// Backdrop
(dark ? rgb(0.055, 0.047, 0.12) : rgb(0.957, 0.949, 0.984)).setFill()
canvas.fill()
func glow(_ c: NSColor, x: CGFloat, y: CGFloat, r: CGFloat) {
    let g = NSGradient(colors: [c, c.withAlphaComponent(0)])!
    g.draw(fromCenter: CGPoint(x: x, y: y), radius: 0, toCenter: CGPoint(x: x, y: y), radius: r, options: [])
}
if dark {
    glow(rgb(0.42, 0.30, 0.86, 0.55), x: 500, y: 1900, r: 1500)
    glow(rgb(0.25, 0.50, 0.96, 0.32), x: 2900, y: 1800, r: 1300)
    glow(rgb(0.85, 0.47, 0.34, 0.22), x: 1600, y: 0, r: 1400)
} else {
    glow(rgb(0.55, 0.45, 0.98, 0.30), x: 500, y: 1900, r: 1500)
    glow(rgb(0.40, 0.65, 1.00, 0.25), x: 2900, y: 1800, r: 1300)
    glow(rgb(1.00, 0.62, 0.45, 0.20), x: 1600, y: 0, r: 1400)
}

// Headline
let para = NSMutableParagraphStyle()
para.alignment = .center
func draw(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, top: CGFloat, width: CGFloat) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para, .kern: size * -0.012]
    let str = NSAttributedString(string: s, attributes: attrs)
    let bounds = str.boundingRect(with: NSSize(width: width, height: 600), options: [.usesLineFragmentOrigin])
    str.draw(with: CGRect(x: (CGFloat(W) - width) / 2, y: CGFloat(H) - top - bounds.height, width: width, height: bounds.height),
             options: [.usesLineFragmentOrigin])
}
draw(opts["title"] ?? "", size: 104, weight: .bold, color: dark ? .white : rgb(0.08, 0.07, 0.16), top: 120, width: 2800)
draw(opts["subtitle"] ?? "", size: 44, weight: .regular, color: dark ? rgb(1, 1, 1, 0.68) : rgb(0.15, 0.13, 0.25, 0.70), top: 268, width: 2200)

// Window (cropped by the bottom edge on purpose)
func place(_ img: NSImage, in rect: CGRect, radius: CGFloat, shadow: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -shadow * 0.35), blur: shadow, color: NSColor.black.withAlphaComponent(dark ? 0.6 : 0.28).cgColor)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor.black.setFill()
    path.fill()
    ctx.restoreGState()
    ctx.saveGState()
    path.addClip()
    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    ctx.restoreGState()
    (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.10)).setStroke()
    path.lineWidth = 2
    path.stroke()
}
let scale: CGFloat = 2560 / window.size.width
let winRect = CGRect(x: (CGFloat(W) - 2560) / 2, y: CGFloat(H) - 450 - window.size.height * scale,
                     width: 2560, height: window.size.height * scale)
place(window, in: winRect, radius: 30, shadow: 90)

if let sheet = overlay {
    // Dim the window like a modal sheet, then drop the sheet from under the title bar.
    ctx.saveGState()
    NSBezierPath(roundedRect: winRect, xRadius: 30, yRadius: 30).addClip()
    NSColor.black.withAlphaComponent(dark ? 0.32 : 0.14).setFill()
    winRect.fill()
    ctx.restoreGState()
    let sw = sheet.size.width * scale * 1.05, sh = sheet.size.height * scale * 1.05
    let sheetRect = CGRect(x: winRect.midX - sw / 2, y: winRect.maxY - 92 - sh, width: sw, height: sh)
    place(sheet, in: sheetRect, radius: 22, shadow: 70)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
