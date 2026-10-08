import AppKit
import SwiftUI

enum GlyphKind: Hashable {
    case brand, machine, sleepingMachine, power, play, stop, terminal, refresh, preferences, quit,
        close, copy, create, delete
}

struct Glyph: Shape {
    let kind: GlyphKind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func line(_ coordinates: [(CGFloat, CGFloat)]) {
            guard let first = coordinates.first else { return }
            path.move(to: point(first.0, first.1))
            for coordinate in coordinates.dropFirst() {
                path.addLine(to: point(coordinate.0, coordinate.1))
            }
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat) {
            path.addRoundedRect(
                in: CGRect(
                    x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                    width: w * rect.width, height: h * rect.height),
                cornerSize: CGSize(width: radius * rect.width, height: radius * rect.height))
        }
        switch kind {
        case .brand:
            path.addPath(Path(PuffArtwork.menuPath(in: rect)))
        case .machine, .sleepingMachine:
            box(0.14, 0.12, 0.72, 0.76, radius: 0.22)
            if kind == .sleepingMachine {
                for x: CGFloat in [0.30, 0.59] {
                    path.move(to: point(x, 0.36))
                    path.addQuadCurve(to: point(x + 0.11, 0.36), control: point(x + 0.055, 0.45))
                }
            } else {
                line([(0.32, 0.38), (0.39, 0.35)])
                line([(0.61, 0.35), (0.68, 0.38)])
            }
            path.move(to: point(0.40, 0.52))
            path.addQuadCurve(to: point(0.60, 0.52), control: point(0.50, 0.67))
            line([(0.33, 0.74), (0.67, 0.74)])
        case .power:
            path.addArc(
                center: point(0.5, 0.54), radius: rect.width * 0.34,
                startAngle: .degrees(-50), endAngle: .degrees(230), clockwise: false)
            line([(0.5, 0.1), (0.5, 0.48)])
        case .play:
            path.move(to: point(0.38, 0.23))
            path.addLine(to: point(0.76, 0.455))
            path.addQuadCurve(to: point(0.76, 0.545), control: point(0.83, 0.5))
            path.addLine(to: point(0.38, 0.77))
            path.addQuadCurve(to: point(0.30, 0.73), control: point(0.30, 0.815))
            path.addLine(to: point(0.30, 0.27))
            path.addQuadCurve(to: point(0.38, 0.23), control: point(0.30, 0.185))
            path.closeSubpath()
        case .stop:
            box(0.24, 0.24, 0.52, 0.52, radius: 0.13)
        case .terminal:
            box(0.07, 0.14, 0.86, 0.72, radius: 0.18)
            path.move(to: point(0.25, 0.35))
            path.addLine(to: point(0.39, 0.47))
            path.addQuadCurve(to: point(0.39, 0.55), control: point(0.43, 0.51))
            path.addLine(to: point(0.25, 0.67))
            line([(0.55, 0.67), (0.76, 0.67)])
        case .refresh:
            path.addArc(
                center: point(0.5, 0.5), radius: rect.width * 0.33,
                startAngle: .degrees(25), endAngle: .degrees(325), clockwise: false)
            path.move(to: point(0.78, 0.1))
            path.addLine(to: point(0.8, 0.24))
            path.addQuadCurve(to: point(0.72, 0.32), control: point(0.812, 0.32))
            path.addLine(to: point(0.58, 0.32))
        case .preferences:
            line([(0.19, 0.16), (0.19, 0.3)])
            line([(0.19, 0.5), (0.19, 0.84)])
            line([(0.5, 0.16), (0.5, 0.57)])
            line([(0.5, 0.77), (0.5, 0.84)])
            line([(0.81, 0.16), (0.81, 0.3)])
            line([(0.81, 0.5), (0.81, 0.84)])
            box(0.07, 0.3, 0.24, 0.2, radius: 0.09)
            box(0.38, 0.57, 0.24, 0.2, radius: 0.09)
            box(0.69, 0.3, 0.24, 0.2, radius: 0.09)
        case .create:
            line([(0.18, 0.5), (0.82, 0.5)])
            line([(0.5, 0.18), (0.5, 0.82)])
        case .delete:
            line([(0.16, 0.27), (0.84, 0.27)])
            box(0.36, 0.12, 0.28, 0.15, radius: 0.07)
            path.move(to: point(0.24, 0.27))
            path.addLine(to: point(0.28, 0.77))
            path.addQuadCurve(to: point(0.38, 0.87), control: point(0.28, 0.87))
            path.addLine(to: point(0.62, 0.87))
            path.addQuadCurve(to: point(0.72, 0.77), control: point(0.72, 0.87))
            path.addLine(to: point(0.76, 0.27))
            line([(0.42, 0.43), (0.43, 0.70)])
            line([(0.58, 0.43), (0.57, 0.70)])
        case .close:
            line([(0.25, 0.25), (0.75, 0.75)])
            line([(0.75, 0.25), (0.25, 0.75)])
        case .copy:
            box(0.33, 0.33, 0.54, 0.54, radius: 0.14)
            path.move(to: point(0.21, 0.64))
            path.addQuadCurve(to: point(0.13, 0.56), control: point(0.13, 0.64))
            path.addLine(to: point(0.13, 0.21))
            path.addQuadCurve(to: point(0.21, 0.13), control: point(0.13, 0.13))
            path.addLine(to: point(0.56, 0.13))
            path.addQuadCurve(to: point(0.64, 0.21), control: point(0.64, 0.13))
        case .quit:
            path.move(to: point(0.43, 0.15))
            path.addLine(to: point(0.28, 0.15))
            path.addQuadCurve(to: point(0.18, 0.25), control: point(0.18, 0.15))
            path.addLine(to: point(0.18, 0.75))
            path.addQuadCurve(to: point(0.28, 0.85), control: point(0.18, 0.85))
            path.addLine(to: point(0.43, 0.85))
            line([(0.42, 0.5), (0.86, 0.5)])
            path.move(to: point(0.70, 0.32))
            path.addLine(to: point(0.84, 0.46))
            path.addQuadCurve(to: point(0.84, 0.54), control: point(0.88, 0.5))
            path.addLine(to: point(0.70, 0.68))
        }
        return path
    }
}

@MainActor
enum BrandIcon {
    static let applicationImage = PuffArtwork.image(size: 512)
    private static var glyphImages: [GlyphKind: NSImage] = [:]

    static func glyphImage(_ kind: GlyphKind) -> NSImage {
        if let image = glyphImages[kind] { return image }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let path = Glyph(kind: kind).path(in: rect.insetBy(dx: 1, dy: 1)).cgPath
            c.setShouldAntialias(true)
            c.addPath(path)
            c.setStrokeColor(NSColor.black.cgColor)
            c.setFillColor(NSColor.black.cgColor)
            c.setLineWidth(1.4)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            if kind == .play || kind == .stop { c.fillPath() } else { c.strokePath() }
            return true
        }
        image.isTemplate = true
        glyphImages[kind] = image
        return image
    }

    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setShouldAntialias(true)
            context.addPath(PuffArtwork.menuPath(in: rect.insetBy(dx: 0.8, dy: 0.8)))
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.4)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
