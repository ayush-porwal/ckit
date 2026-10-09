import AppKit
import Foundation

// Compile with PuffArtwork.swift so the app and exported icons share one drawing.
@main
struct GenerateIcons {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let destination = root.appendingPathComponent("CKit/Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var images: [[String: String]] = []
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let filename = "icon-\(size)@\(scale)x.png"
                try renderIcon(pixels: size * scale).write(
                    to: destination.appendingPathComponent(filename))
                images.append([
                    "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x",
                    "filename": filename,
                ])
            }
        }
        let manifest: [String: Any] = [
            "images": images, "info": ["author": "xcode", "version": 1],
        ]
        try JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]
        )
        .write(to: destination.appendingPathComponent("Contents.json"))
        try renderIcon(pixels: 512).write(
            to: root.appendingPathComponent("Design/puff-app-icon.png"))
        let mark = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let c = NSGraphicsContext(bitmapImageRep: mark)!.cgContext
        c.translateBy(x: 0, y: 40)
        c.scaleBy(x: 2, y: -2)
        c.addPath(PuffArtwork.menuPath(in: CGRect(x: 0.8, y: 0.8, width: 18.4, height: 18.4)))
        c.setStrokeColor(NSColor.black.cgColor)
        c.setLineWidth(1.4)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.strokePath()
        try mark.representation(using: .png, properties: [:])!
            .write(to: root.appendingPathComponent("Design/puff-menubar.png"))
        let menuSVG = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><title>Ckit Puff menu bar face</title><path d="\(svgPath(PuffArtwork.menuPath(in: CGRect(x: 0, y: 0, width: 24, height: 24))))" fill="none" stroke="currentColor" stroke-width="1.826" stroke-linecap="round" stroke-linejoin="round"/></svg>
            """
        try menuSVG.write(
            to: root.appendingPathComponent("Design/ckit-mark.svg"), atomically: true,
            encoding: .utf8)
        let appSVG = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>Ckit Puff</title>
            <defs><linearGradient id="body" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#69746f"/><stop offset=".5" stop-color="#424d48"/><stop offset="1" stop-color="#252f2b"/></linearGradient><linearGradient id="mint" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#d2edcd"/><stop offset="1" stop-color="#81b299"/></linearGradient><filter id="shadow" x="-25%" y="-25%" width="150%" height="150%"><feDropShadow dx="0" dy="5" stdDeviation="2.5" flood-color="#152b20" flood-opacity=".25"/></filter></defs>
            <ellipse cx="128" cy="231" rx="75" ry="8" fill="#223c2d" opacity=".08"/>
            <g fill="url(#mint)"><rect x="88" y="193" width="28" height="30" rx="14"/><rect x="142" y="193" width="28" height="30" rx="14"/></g>
            <path d="\(svgPath(PuffArtwork.bodyPath()))" fill="url(#body)" stroke="#9aaa9c" stroke-opacity=".7" stroke-width="1.8" stroke-linejoin="round" filter="url(#shadow)"/>
            <path d="M65 86C65 65 72 57 88 55C108 51 115 65 124 74" stroke="#c6d2c5" stroke-opacity=".28" stroke-width="2.5" fill="none" stroke-linecap="round"/>
            <path d="M83 117Q94 100 105 117M151 117Q162 100 173 117" fill="none" stroke="#e9edda" stroke-width="7" stroke-linecap="round"/>
            <path d="M117 134Q128 158 140 134" fill="none" stroke="#c5dfba" stroke-width="5" stroke-linecap="round"/>
            <g fill="#b4c2a2" opacity=".3"><ellipse cx="80" cy="132" rx="10" ry="5"/><ellipse cx="176" cy="132" rx="10" ry="5"/></g>
            <rect x="93" y="172" width="70" height="8" rx="4" fill="#1e3327"/><rect x="96" y="174" width="32" height="3" rx="1.5" fill="#748c71"/><circle cx="155" cy="176" r="2" fill="#b9d8ae"/>
            </svg>
            """
        try appSVG.write(
            to: root.appendingPathComponent("Design/ckit-app-icon.svg"), atomically: true,
            encoding: .utf8)
        print("Generated all 10 macOS app icon sizes for Puff.")
    }

    static func svgPath(_ path: CGPath) -> String {
        var commands: [String] = []
        func point(_ p: CGPoint) -> String {
            String(
                format: "%.4f %.4f", locale: Locale(identifier: "en_US_POSIX"), Double(p.x),
                Double(p.y))
        }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: commands.append("M" + point(e.points[0]))
            case .addLineToPoint: commands.append("L" + point(e.points[0]))
            case .addQuadCurveToPoint:
                commands.append("Q" + point(e.points[0]) + " " + point(e.points[1]))
            case .addCurveToPoint:
                commands.append(
                    "C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2]))
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        return commands.joined(separator: " ")
    }

    static func renderIcon(pixels: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: 1, y: -1)
        PuffArtwork.draw(in: ctx, rect: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return rep.representation(using: .png, properties: [:])!
    }
}
