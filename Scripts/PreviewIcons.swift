import AppKit

// Renders actual native paths at their real point sizes and at 4× for inspection.
@main struct PreviewIcons {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let width = 760
        let height = 462
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width * 2, pixelsHigh: height * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        let c = graphics.cgContext
        c.scaleBy(x: 2, y: 2)
        c.translateBy(x: 0, y: CGFloat(height))
        c.scaleBy(x: 1, y: -1)
        c.setShouldAntialias(true)
        c.setFillColor(NSColor(calibratedWhite: 0.98, alpha: 1).cgColor)
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        PuffArtwork.draw(in: c, rect: CGRect(x: 26, y: 25, width: 225, height: 225))
        let kinds: [GlyphKind] = [
            .brand, .machine, .sleepingMachine, .power, .play, .stop, .terminal, .refresh, .delete,
            .quit, .copy, .close,
        ]
        for (index, kind) in kinds.enumerated() {
            let x = CGFloat(276 + (index % 6) * 76)
            let y = CGFloat(55 + (index / 6) * 95)
            glyph(kind, in: c, rect: CGRect(x: x, y: y, width: 50, height: 50), color: .black)
        }
        for dark in [false, true] {
            let y: CGFloat = dark ? 367 : 278
            c.setFillColor(
                (dark
                    ? NSColor(calibratedWhite: 0.14, alpha: 1)
                    : NSColor(calibratedWhite: 0.94, alpha: 1)).cgColor)
            c.fill(CGRect(x: 24, y: y, width: 712, height: 69))
            for (index, kind) in kinds.enumerated() {
                glyph(
                    kind, in: c,
                    rect: CGRect(
                        x: CGFloat(48 + index * 57), y: y + 24, width: kind == .brand ? 20 : 18,
                        height: kind == .brand ? 20 : 18), color: dark ? .white : .black)
            }
        }
        let url = URL(fileURLWithPath: "Design/smooth-icons-preview.png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        print("Rendered smooth native paths at 18/20 pt and enlarged sizes.")
    }

    static func glyph(_ kind: GlyphKind, in c: CGContext, rect: CGRect, color: NSColor) {
        c.saveGState()
        defer { c.restoreGState() }
        if kind == .brand {
            c.addPath(
                PuffArtwork.menuPath(
                    in: rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)))
        } else {
            c.addPath(
                Glyph(kind: kind).path(in: rect.insetBy(dx: rect.width / 18, dy: rect.height / 18))
                    .cgPath)
        }
        c.setLineWidth(rect.width * 1.4 / (kind == .brand ? 20 : 18))
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.setStrokeColor(color.cgColor)
        c.setFillColor(color.cgColor)
        if kind == .play || kind == .stop { c.fillPath() } else { c.strokePath() }
    }
}
