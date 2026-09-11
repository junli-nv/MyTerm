import AppKit

// Vector artwork rendered at every macOS icon size; no external assets required.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func render(_ pixels: Int, filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    let tile = rounded(NSRect(x: 64, y: 64, width: 896, height: 896), 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
    color(0x142332).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x30495C), ending: color(0x101A29))!.draw(in: tile, angle: -75)
    color(0x667E8C).withAlphaComponent(0.45).setStroke(); tile.lineWidth = 3; tile.stroke()

    // Three network tiles connect to the terminal, echoing a multi-tool workspace.
    for (x, y, tint) in [(600.0, 653.0, UInt32(0xFFAA45)), (709.0, 596.0, 0x39BFEF), (652.0, 490.0, 0x54D6AF)] {
        let path = rounded(NSRect(x: x, y: y, width: 177, height: 177), 40)
        NSGradient(starting: color(tint), ending: color(tint).blended(withFraction: 0.22, of: .black)!)!.draw(in: path, angle: -90)
        NSColor.white.withAlphaComponent(0.25).setStroke(); path.lineWidth = 3; path.stroke()
    }
    let terminal = rounded(NSRect(x: 151, y: 226, width: 620, height: 506), 62)
    NSGraphicsContext.saveGraphicsState()
    shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.set()
    color(0x0B121E).setFill(); terminal.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0x567084).setStroke(); terminal.lineWidth = 7; terminal.stroke()
    for (index, tint) in [UInt32(0xFF786E), 0xFFD16F, 0x63D4A3].enumerated() {
        color(tint).setFill()
        NSBezierPath(ovalIn: NSRect(x: 194 + index * 47, y: 664, width: 23, height: 23)).fill()
    }
    color(0x28394B).setFill(); NSRect(x: 178, y: 629, width: 566, height: 3).fill()
    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: 251, y: 545)); prompt.line(to: NSPoint(x: 369, y: 449)); prompt.line(to: NSPoint(x: 251, y: 353))
    prompt.lineWidth = 42; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round
    color(0x64E4BD).setStroke(); prompt.stroke()
    let cursor = rounded(NSRect(x: 424, y: 339, width: 171, height: 37), 16)
    color(0xE9F6FC).setFill(); cursor.fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
}
for size in [16, 32, 128, 256, 512] {
    try render(size, filename: "icon_\(size)x\(size).png")
    try render(size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
