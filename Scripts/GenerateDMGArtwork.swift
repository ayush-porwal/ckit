import AppKit
import CoreText

// Compile with PuffArtwork.swift; the installer keeps the app's exact character.
@main
struct GenerateDMGArtwork {
    static let width = 640
    static let height = 420

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "Ckit.DMG", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Usage: generate-dmg-artwork OUTPUT.tiff"
            ])
        }
        let images = [render(scale: 1), render(scale: 2)]
        let data = NSBitmapImageRep.tiffRepresentationOfImageReps(
            in: images, using: .packBits, factor: 0)!
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }

    static func render(scale: Int) -> NSBitmapImageRep {
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .retagging(with: .sRGB)!
        let c = NSGraphicsContext(bitmapImageRep: image)!.cgContext
        c.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        c.translateBy(x: 0, y: CGFloat(height))
        c.scaleBy(x: 1, y: -1)
        c.setShouldAntialias(true)
        c.setFillColor(Self.color(0xf6f3e9))
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // A medium sage keeps native black and white Finder labels legible.
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: 0, y: 139))
        wave.addCurve(
            to: CGPoint(x: 272, y: 139), control1: CGPoint(x: 100, y: 182),
            control2: CGPoint(x: 151, y: 102))
        wave.addCurve(
            to: CGPoint(x: 640, y: 131), control1: CGPoint(x: 395, y: 176),
            control2: CGPoint(x: 470, y: 179))
        wave.addLine(to: CGPoint(x: 640, y: 420))
        wave.addLine(to: CGPoint(x: 0, y: 420))
        wave.closeSubpath()
        c.addPath(wave)
        c.setFillColor(Self.color(0x70786c))
        c.fillPath()

        PuffArtwork.draw(in: c, rect: CGRect(x: 44, y: 32, width: 73, height: 73))
        text("Hello, Ckit.", in: c, x: 134, y: 49, size: 30, color: 0x35433b, bold: true)
        sparkle(in: c, x: 581, y: 75, radius: 10, color: 0x9ba987)
        sparkle(in: c, x: 553, y: 99, radius: 5, color: 0xbdc5a7)

        c.setStrokeColor(Self.color(0xe8eedb))
        c.setLineWidth(3)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.setLineDash(phase: 0, lengths: [3, 8])
        c.move(to: CGPoint(x: 270, y: 252))
        c.addLine(to: CGPoint(x: 364, y: 252))
        c.strokePath()
        c.setLineDash(phase: 0, lengths: [])
        c.move(to: CGPoint(x: 358, y: 240))
        c.addLine(to: CGPoint(x: 370, y: 252))
        c.addLine(to: CGPoint(x: 358, y: 264))
        c.strokePath()
        text("Drag Ckit into", in: c, x: 320, y: 281, size: 12, color: 0xf6f3e9, centered: true)
        text("Applications", in: c, x: 320, y: 299, size: 12, color: 0xf6f3e9, centered: true)
        // Set the logical size after drawing: NSGraphicsContext otherwise adds
        // its own Retina scale on top of the explicit scale above.
        image.size = NSSize(width: width, height: height)
        return image
    }

    static func text(
        _ value: String, in c: CGContext, x: CGFloat, y: CGFloat, size: CGFloat,
        color: UInt32, bold: Bool = false, centered: Bool = false
    ) {
        let base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .medium)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size)!
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: value, attributes: [
                .font: font, .foregroundColor: NSColor(cgColor: Self.color(color))!
            ]))
        var ascent: CGFloat = 0
        let length = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        c.saveGState()
        c.translateBy(x: centered ? x - CGFloat(length) / 2 : x, y: y + ascent)
        c.scaleBy(x: 1, y: -1)
        c.textMatrix = .identity
        c.textPosition = .zero
        CTLineDraw(line, c)
        c.restoreGState()
    }

    static func sparkle(in c: CGContext, x: CGFloat, y: CGFloat, radius: CGFloat, color: UInt32) {
        c.move(to: CGPoint(x: x, y: y - radius))
        c.addQuadCurve(to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x + 2, y: y - 2))
        c.addQuadCurve(to: CGPoint(x: x, y: y + radius), control: CGPoint(x: x + 2, y: y + 2))
        c.addQuadCurve(to: CGPoint(x: x - radius, y: y), control: CGPoint(x: x - 2, y: y + 2))
        c.addQuadCurve(to: CGPoint(x: x, y: y - radius), control: CGPoint(x: x - 2, y: y - 2))
        c.closePath()
        c.setFillColor(Self.color(color))
        c.fillPath()
    }

    static func color(_ hex: UInt32) -> CGColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1).cgColor
    }
}
