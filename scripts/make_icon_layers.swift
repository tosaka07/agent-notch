import AppKit

// Same derivation as ProductMark: ring -> remove the middle 5 cells of the top edge -> center 3x3
let N = 13
func ringCells() -> [(Int, Int)] {
    let center = 6.0, radius = 5.2
    var out: [(Int, Int)] = []
    for y in 0..<N { for x in 0..<N {
        let dx = Double(x) - center, dy = Double(y) - center
        let d = (dx*dx + dy*dy).squareRoot()
        if d > radius - 0.75 && d < radius + 0.75 { out.append((x, y)) }
    } }
    return out
}
let cutout = 4...8
let outline = ringCells().filter { !($0.1 == 1 && cutout.contains($0.0)) }
let pupil = (5...7).flatMap { r in (5...7).map { ($0, r) } }

func ascii(_ cells: [(Int, Int)], _ t: String) {
    var g = Array(repeating: Array(repeating: ".", count: N), count: N)
    for c in cells { g[c.1][c.0] = "#" }
    print("--- \(t) ---"); for (r, row) in g.enumerated() { print(String(format: "%2d ", r) + row.joined()) }
}
ascii(outline + pupil, "outline + pupil")

// Write out the layer PNGs
func writePNG(_ path: String, size: Int, draw: (CGContext, CGFloat) -> Void) {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    draw(ctx, CGFloat(size))
    guard let img = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let out = CommandLine.arguments[1]
// Foreground layer: the mark itself. Per Apple's guidance, draw it as a square
// that includes its own padding and leave the mask, blur, and specular
// highlights to the system.
func drawMark(_ ctx: CGContext, _ s: CGFloat) {
    // Keep the artwork to roughly 62% of the shorter side (Apple's grid guideline).
    let inset = s * 0.19
    let box = s - inset * 2
    let pitch = box / CGFloat(N)
    let dot = pitch * 2 / 3
    func fill(_ cells: [(Int, Int)], alpha: CGFloat) {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        for (col, row) in cells {
            let x = inset + CGFloat(col) * pitch + (pitch - dot) / 2
            let y = s - inset - CGFloat(row + 1) * pitch + (pitch - dot) / 2
            ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
        }
    }
    fill(outline, alpha: 1.0)
    fill(pupil, alpha: 0.35)
}

writePNG("\(out)/layer-foreground.png", size: 1024) { ctx, s in drawMark(ctx, s) }
writePNG("\(out)/layer-background.png", size: 1024) { ctx, s in
    // The background layer is flat, matching the black of the notch. The system adds the glass.
    ctx.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.063, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
}
writePNG("\(out)/icon-1024.png", size: 1024) { ctx, s in
    ctx.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.063, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    drawMark(ctx, s)
}
