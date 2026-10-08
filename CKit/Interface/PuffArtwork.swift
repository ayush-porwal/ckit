import AppKit

// Smooth, shared vector geometry for the app icon and menu bar face.
enum PuffArtwork {
    enum Mood { case happy, sleepy, working, concerned }

    // Adjacent Bézier handles follow the same tangent at each lobe and valley.
    // Rounded stroke joins alone cannot remove a cusp in the outline itself.
    static func outlinePath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 5.4, y: 9))
        let curves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (5.2, 8.4, 5, 7.8, 5, 7),
            (5, 4.8, 6.8, 3, 9, 3),
            (10.5, 3, 11.7, 3.85, 12.4, 5),
            (12.75, 5.575, 13.15, 5.6, 13.65, 5.25),
            (14.45, 4.69, 15.25, 4.4, 16.2, 4.4),
            (18.3, 4.4, 20, 6.1, 20, 8.2),
            (20, 8.6, 19.95, 8.95, 19.85, 9.3),
            (19.75, 9.65, 19.85, 9.95, 20.2, 10.1),
            (22, 10.87143, 23, 12.2, 23, 14.5),
            (23, 17.8, 20.4, 20.4, 17.1, 20.4),
            (15.4, 20.4, 14.3, 20.65, 12.5, 20.65),
            (10.7, 20.65, 9.7, 20.4, 7.8, 20.4),
            (4.2, 20.4, 1.3, 17.7, 1.3, 14.7),
            (1.3, 12.1, 2.65, 10.5, 4.65, 9.75),
            (5.25, 9.525, 5.6, 9.6, 5.4, 9),
        ]
        for (a, b, c, d, x, y) in curves {
            p.addCurve(
                to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b),
                control2: CGPoint(x: c, y: d))
        }
        p.closeSubpath()
        return p
    }

    private static func transform(_ path: CGPath, into rect: CGRect) -> CGPath {
        var t = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return path.copy(using: &t)!
    }

    static func bodyPath() -> CGPath {
        transform(outlinePath(), into: CGRect(x: 11, y: 12, width: 234, height: 224))
    }

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    private static func fill(
        _ c: CGContext, _ path: CGPath, colors: [UInt32], start: CGPoint, end: CGPoint
    ) {
        c.saveGState()
        c.addPath(path)
        c.clip()
        let g = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { color($0) } as CFArray,
            locations: nil)!
        c.drawLinearGradient(
            g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }

    private static func stroke(
        _ c: CGContext, _ p: CGPath, hex: UInt32, width: CGFloat, alpha: CGFloat = 1
    ) {
        c.addPath(p)
        c.setStrokeColor(color(hex, alpha: alpha))
        c.setLineWidth(width)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.strokePath()
    }

    static func draw(in c: CGContext, rect: CGRect, mood: Mood = .happy) {
        c.saveGState()
        defer { c.restoreGState() }
        c.translateBy(x: rect.minX, y: rect.minY)
        c.scaleBy(x: rect.width / 256, y: rect.height / 256)
        c.setFillColor(color(0x223c2d, alpha: 0.08))
        c.fillEllipse(in: CGRect(x: 53, y: 223, width: 150, height: 16))
        for x: CGFloat in [88, 142] {
            let foot = CGPath(
                roundedRect: CGRect(x: x, y: 193, width: 28, height: 30), cornerWidth: 14,
                cornerHeight: 14, transform: nil)
            fill(
                c, foot, colors: [0xd2edcd, 0x81b299], start: CGPoint(x: x, y: 195),
                end: CGPoint(x: x, y: 223))
        }
        let shell = bodyPath()
        c.saveGState()
        c.setShadow(
            offset: CGSize(width: 0, height: 5), blur: 5, color: color(0x152b20, alpha: 0.25))
        c.addPath(shell)
        c.setFillColor(color(0x35433b))
        c.fillPath()
        c.restoreGState()
        fill(
            c, shell, colors: [0x69746f, 0x424d48, 0x252f2b], start: CGPoint(x: 45, y: 40),
            end: CGPoint(x: 208, y: 210))
        stroke(c, shell, hex: 0x9aaa9c, width: 1.8, alpha: 0.7)
        let shine = CGMutablePath()
        shine.move(to: CGPoint(x: 65, y: 86))
        shine.addCurve(
            to: CGPoint(x: 88, y: 55), control1: CGPoint(x: 65, y: 65),
            control2: CGPoint(x: 72, y: 57))
        shine.addCurve(
            to: CGPoint(x: 124, y: 74), control1: CGPoint(x: 108, y: 51),
            control2: CGPoint(x: 115, y: 65))
        stroke(c, shine, hex: 0xc6d2c5, width: 2.5, alpha: 0.28)
        let face = CGMutablePath()
        for x: CGFloat in [83, 151] {
            face.move(to: CGPoint(x: x, y: 117))
            switch mood {
            case .happy:
                face.addQuadCurve(
                    to: CGPoint(x: x + 22, y: 117), control: CGPoint(x: x + 11, y: 100))
            case .sleepy:
                face.addQuadCurve(
                    to: CGPoint(x: x + 22, y: 117), control: CGPoint(x: x + 11, y: 129))
            case .working:
                face.addLine(to: CGPoint(x: x + 22, y: 117))
            case .concerned:
                face.addLine(to: CGPoint(x: x + 15, y: 113))
            }
        }
        stroke(c, face, hex: 0xe9edda, width: 7)
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 117, y: 134))
        mouth.addQuadCurve(
            to: CGPoint(x: 140, y: 134), control: CGPoint(x: 128, y: mood == .concerned ? 127 : 158)
        )
        stroke(c, mouth, hex: 0xc5dfba, width: 5)
        c.setFillColor(color(0xb4c2a2, alpha: 0.3))
        for x: CGFloat in [70, 166] {
            c.fillEllipse(in: CGRect(x: x, y: 127, width: 20, height: 10))
        }
        let slot = CGPath(
            roundedRect: CGRect(x: 93, y: 172, width: 70, height: 8), cornerWidth: 4,
            cornerHeight: 4, transform: nil)
        c.addPath(slot)
        c.setFillColor(color(0x1e3327))
        c.fillPath()
        c.setFillColor(color(0x748c71))
        c.addPath(
            CGPath(
                roundedRect: CGRect(x: 96, y: 174, width: 32, height: 3), cornerWidth: 1.5,
                cornerHeight: 1.5, transform: nil))
        c.fillPath()
        c.setFillColor(color(mood == .sleepy ? 0x748c71 : 0xb9d8ae))
        c.fillEllipse(in: CGRect(x: 153, y: 174, width: 4, height: 4))
    }

    static func menuPath(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.addPath(outlinePath())
        p.move(to: CGPoint(x: 8.1, y: 11.5))
        p.addQuadCurve(to: CGPoint(x: 10.1, y: 11.5), control: CGPoint(x: 9.1, y: 9.8))
        p.move(to: CGPoint(x: 14, y: 11.5))
        p.addQuadCurve(to: CGPoint(x: 16, y: 11.5), control: CGPoint(x: 15, y: 9.8))
        p.move(to: CGPoint(x: 10.1, y: 14.7))
        p.addQuadCurve(to: CGPoint(x: 13.9, y: 14.7), control: CGPoint(x: 12, y: 17.1))
        return transform(p, into: rect)
    }

    @MainActor static func image(size: CGFloat, mood: Mood = .happy) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: c, rect: rect, mood: mood)
            return true
        }
    }
}
