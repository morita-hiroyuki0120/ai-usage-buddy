import AppKit
import Testing
@testable import AIUsageBuddy

@Suite
@MainActor
struct CharacterArtworkTests {
    @Test("全状態が固定サイズ・上下3pt以上の透明余白を持つテンプレート画像")
    func menuImageMargins() throws {
        for state in CharacterState.allCases {
            let image = MenuBarIconCache.image(for: state)
            #expect(image.isTemplate)
            #expect(image.size == NSSize(width: 26, height: 22))
            let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
            #expect(bitmap.pixelsWide == 52)
            #expect(bitmap.pixelsHigh == 44)
            var visiblePixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let alpha = try #require(bitmap.colorAt(x: x, y: y)).alphaComponent
                    if y < 6 || y >= 38 {
                        #expect(alpha == 0, "\(state): 余白に描画がはみ出している (\(x), \(y))")
                    }
                    if alpha > 0 { visiblePixels += 1 }
                }
            }
            #expect(visiblePixels > 60, "\(state): 空のアイコンではない")
        }
    }

    @Test("状態ごとに異なるシルエットをキャッシュし、繰り返し取得で再描画しない")
    func distinctStableCachedImages() throws {
        var rendered = Set<Data>()
        for state in CharacterState.allCases {
            let first = MenuBarIconCache.image(for: state)
            #expect(first === MenuBarIconCache.image(for: state))
            let bitmap = try #require(first.representations.first as? NSBitmapImageRep)
            rendered.insert(try #require(bitmap.representation(using: .png, properties: [:])))
        }
        #expect(rendered.count == CharacterState.allCases.count)
    }

    @Test("大きい差し替え画像にも上下余白と縦横比が適用される")
    func customImageIsContained() throws {
        let source = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 160,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let sourceContext = try #require(NSGraphicsContext(bitmapImageRep: source)).cgContext
        sourceContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        sourceContext.fill(CGRect(x: 0, y: 0, width: 80, height: 160))
        let custom = NSImage(size: NSSize(width: 80, height: 160))
        custom.addRepresentation(source)
        let image = CatDrawing.menuImage(for: .normal, custom: custom)
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        var xs: [Int] = []
        var ys: [Int] = []
        for y in 0..<44 {
            for x in 0..<52 where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                xs.append(x)
                ys.append(y)
            }
        }
        let width = try #require(xs.max()) - #require(xs.min()) + 1
        let height = try #require(ys.max()) - #require(ys.min()) + 1
        #expect(width == 16)
        #expect(height == 32)
        #expect(ys.min() == 6)
        #expect(ys.max() == 37)
    }
}
