import AppKit

/// Local candidate only; the cat is drawn by the app's shared CatDrawing source.
@main
@MainActor
enum RenderAppIcon {
    private struct Contents: Decodable {
        struct Entry: Decodable {
            let idiom: String
            let size: String
            let scale: String
            let filename: String
        }
        let images: [Entry]
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contents = try JSONDecoder().decode(
            Contents.self, from: Data(contentsOf: output.appendingPathComponent("Contents.json"))
        )
        let aqua = NSAppearance(named: .aqua)!
        var teal = NSColor.systemTeal
        aqua.performAsCurrentDrawingAppearance {
            teal = NSColor.systemTeal.usingColorSpace(.sRGB)!
        }
        for entry in contents.images {
            guard entry.idiom == "mac", !entry.filename.contains("/"),
                  let points = Int(entry.size.components(separatedBy: "x")[0]),
                  let scale = Int(entry.scale.replacingOccurrences(of: "x", with: "")),
                  [16, 32, 128, 256, 512].contains(points), [1, 2].contains(scale)
            else { throw CocoaError(.coderInvalidValue) }
            let pixels = points * scale
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            context.setShouldAntialias(true)
            context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            context.translateBy(x: 0, y: 1024)
            context.scaleBy(x: 1, y: -1)
            let tile = CGPath(
                roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                cornerWidth: 200, cornerHeight: 200, transform: nil
            )
            context.saveGState()
            context.addPath(tile)
            context.clip()
            let colors = [
                NSColor(srgbRed: 0.09, green: 0.18, blue: 0.29, alpha: 1).cgColor,
                NSColor(srgbRed: 0.025, green: 0.055, blue: 0.10, alpha: 1).cgColor,
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: colors as CFArray, locations: [0, 1]
            )!
            context.drawLinearGradient(
                gradient, start: CGPoint(x: 170, y: 64), end: CGPoint(x: 850, y: 960), options: []
            )
            context.restoreGState()
            context.setShadow(
                offset: CGSize(width: 0, height: 12), blur: 20,
                color: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28).cgColor
            )
            CatDrawing.draw(
                in: context, rect: CGRect(x: 72, y: 224, width: 880, height: 563.2),
                state: .normal, elapsed: CatDrawing.menuFrameElapsed(for: .normal, frameIndex: 0),
                color: teal.cgColor, template: false
            )
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: output.appendingPathComponent(entry.filename), options: .atomic)
        }
        print("Generated \(contents.images.count) macOS icon PNGs; candidate, not design-approved.")
    }
}
