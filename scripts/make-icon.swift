// Renders Kitfold's app icon (three folded layers on a rounded square) to a 1024px PNG.
// Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Squircle-ish background with a deep indigo → violet gradient.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.15, blue: 0.36, alpha: 1),
                    NSColor(srgbRed: 0.33, green: 0.24, blue: 0.62, alpha: 1)])!
    .draw(in: bg, angle: -60)

// Three stacked "kits", each folded at the corner, in the agents' accent colors.
let colors: [NSColor] = [
    NSColor(srgbRed: 0.30, green: 0.55, blue: 0.96, alpha: 1),  // blue
    NSColor(srgbRed: 0.49, green: 0.55, blue: 0.97, alpha: 1),  // periwinkle
    NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1),  // warm orange
]
for (i, color) in colors.enumerated() {
    let w: CGFloat = 470, h: CGFloat = 300
    let x = (size - w) / 2 + CGFloat(i - 1) * 34
    let y = 300 + CGFloat(i) * 92
    let fold: CGFloat = 90
    let p = NSBezierPath()
    p.move(to: CGPoint(x: x + 36, y: y))
    p.line(to: CGPoint(x: x + w - 36, y: y))
    p.curve(to: CGPoint(x: x + w, y: y + 36), controlPoint1: CGPoint(x: x + w - 16, y: y), controlPoint2: CGPoint(x: x + w, y: y + 16))
    p.line(to: CGPoint(x: x + w, y: y + h - fold))
    p.line(to: CGPoint(x: x + w - fold, y: y + h))
    p.line(to: CGPoint(x: x + 36, y: y + h))
    p.curve(to: CGPoint(x: x, y: y + h - 36), controlPoint1: CGPoint(x: x + 16, y: y + h), controlPoint2: CGPoint(x: x, y: y + h - 16))
    p.line(to: CGPoint(x: x, y: y + 36))
    p.curve(to: CGPoint(x: x + 36, y: y), controlPoint1: CGPoint(x: x, y: y + 16), controlPoint2: CGPoint(x: x + 16, y: y))
    p.close()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    color.setFill()
    p.fill()
    ctx.restoreGState()
    // The folded corner.
    let corner = NSBezierPath()
    corner.move(to: CGPoint(x: x + w, y: y + h - fold))
    corner.line(to: CGPoint(x: x + w - fold, y: y + h - fold))
    corner.line(to: CGPoint(x: x + w - fold, y: y + h))
    corner.close()
    color.blended(withFraction: 0.45, of: .white)!.setFill()
    corner.fill()
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
