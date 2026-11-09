import AppKit

/// Both surfaces use the same vector silhouette. Coordinates are a 100 × 64 stage.
/// Both surfaces share five held poses per cycle, without interpolation.
enum CatDrawing {
    static let menuSize = CGSize(width: 26, height: 22)
    static let menuArtworkRect = CGRect(x: 1, y: 3, width: 24, height: 16)

    static func cycleDuration(for state: CharacterState) -> Double {
        switch state {
        case .energetic: return 0.7
        case .normal: return 1.6
        case .tired: return 3.2
        case .sleeping: return 3.6
        case .unknown: return 0
        }
    }

    /// メニューバーアイコンのアニメーションフレームレート（4〜8fpsの低負荷帯の上限）。
    static let menuAnimationFPS = 8.0

    /// 状態ごとのサイクルを何フレームに量子化するか。
    /// unknown は1フレーム（静止）。
    static func menuFrameCount(for state: CharacterState) -> Int {
        state == .unknown ? 1 : 5
    }

    /// 経過時間から現在のフレーム番号（0...menuFrameCount-1）を求める。
    static func menuFrameIndex(for state: CharacterState, elapsed: Double) -> Int {
        let count = menuFrameCount(for: state)
        guard count > 1 else { return 0 }
        let duration = cycleDuration(for: state)
        return Int(elapsed / duration * Double(count)) % count
    }

    /// フレーム番号を描画用の経過時間へ戻す（フレーム中心の位相）。
    /// ポップオーバーも同じ5枚のポーズを使用する。
    static func menuFrameElapsed(for state: CharacterState, frameIndex: Int) -> Double {
        let count = menuFrameCount(for: state)
        let duration = cycleDuration(for: state)
        guard count > 0, duration > 0 else { return 0 }
        return (Double(frameIndex % count) + 0.5) / Double(count) * duration
    }

    static func draw(in context: CGContext, rect: CGRect, state: CharacterState,
                     elapsed: Double? = nil, color: CGColor, template: Bool) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 100, y: rect.height / 64)
        context.setFillColor(color)
        context.setStrokeColor(color)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let frame = elapsed.map { menuFrameIndex(for: state, elapsed: $0) } ?? 0
        // Each state has five explicitly drawn poses, held without interpolation.

        func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            context.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
        }
        func stroke(_ points: [CGPoint], width: Double) {
            let path = CGMutablePath()
            path.addLines(between: points)
            context.addPath(path)
            context.setLineWidth(width)
            context.strokePath()
        }
        func tail(_ start: CGPoint, _ end: CGPoint, _ c1: CGPoint, _ c2: CGPoint, width: Double = 7) {
            let path = CGMutablePath()
            path.move(to: start)
            path.addCurve(to: end, control1: c1, control2: c2)
            context.addPath(path)
            context.setLineWidth(width)
            context.strokePath()
        }
        func feature(_ rect: CGRect, sleeping: Bool = false) {
            context.saveGState()
            // Actual transparent eye cutouts keep templates readable on any menu background.
            if template {
                context.setBlendMode(.clear)
            } else {
                context.setFillColor(NSColor.white.cgColor)
            }
            if sleeping {
                context.fill(rect)
            } else {
                context.fillEllipse(in: rect)
            }
            context.restoreGState()
        }
        func head(x: Double, y: Double, tilt: Double = 0, sleepy: Bool = false) {
            context.saveGState()
            context.translateBy(x: x + 14, y: y + 15)
            context.rotate(by: tilt)
            context.translateBy(x: -14, y: -15)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 1, y: 15))
            path.addLine(to: CGPoint(x: 1, y: 0))
            path.addLine(to: CGPoint(x: 11, y: 7))
            path.addLine(to: CGPoint(x: 19, y: 6))
            path.addLine(to: CGPoint(x: 27, y: 0))
            path.addLine(to: CGPoint(x: 29, y: 17))
            path.addQuadCurve(to: CGPoint(x: 15, y: 30), control: CGPoint(x: 32, y: 30))
            path.addQuadCurve(to: CGPoint(x: 1, y: 15), control: CGPoint(x: 0, y: 30))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
            feature(CGRect(x: 9, y: 16, width: 4, height: sleepy ? 2 : 4), sleeping: sleepy)
            feature(CGRect(x: 21, y: 16, width: 4, height: sleepy ? 2 : 4), sleeping: sleepy)
            context.restoreGState()
        }

        switch state {
        case .energetic:
            // Five hand-posed hurdle strides: push off, rise, clear, land, recover.
            // The passing bar makes forward travel readable without moving the icon.
            let bodyY = [31.0, 22, 18, 23, 31][frame]
            let headTilt = [-0.05, -0.16, -0.08, 0.12, 0.06][frame]
            let hurdleX = [88.0, 72, 51, 29, 9][frame]
            stroke([CGPoint(x: hurdleX - 6, y: 51), CGPoint(x: hurdleX + 6, y: 51)], width: 3)
            stroke([CGPoint(x: hurdleX, y: 51), CGPoint(x: hurdleX, y: 61)], width: 3)

            tail(CGPoint(x: 29, y: bodyY + 9),
                 CGPoint(x: 7, y: [27.0, 32, 25, 14, 21][frame]),
                 CGPoint(x: 17, y: bodyY + 8),
                 CGPoint(x: 7, y: bodyY + 1))
            // Two joints per leg. Paws tuck under the belly at the apex, then reach
            // forward for landing; the hind legs trail behind during ascent.
            let legs: [[(Double, Double)]] = [
                [(42, 50), (29, 60), (48, 51), (39, 59), (71, 48), (66, 53), (81, 43), (86, 40)],
                [(24, 45), (11, 51), (33, 44), (23, 53), (73, 36), (84, 33), (79, 30), (91, 26)],
                [(28, 40), (43, 40), (38, 43), (49, 39), (77, 37), (87, 34), (82, 31), (93, 29)],
                [(32, 43), (44, 45), (43, 44), (53, 41), (70, 48), (77, 58), (81, 44), (87, 57)],
                [(23, 46), (13, 51), (38, 53), (31, 60), (63, 53), (56, 58), (77, 51), (83, 60)],
            ]
            for (leg, rootX) in [34.0, 43, 63, 70].enumerated() {
                let knee = legs[frame][leg * 2]
                let paw = legs[frame][leg * 2 + 1]
                stroke([CGPoint(x: rootX, y: bodyY + 14),
                        CGPoint(x: knee.0, y: knee.1), CGPoint(x: paw.0, y: paw.1)], width: 6)
            }
            ellipse(25, bodyY, 51, 21)
            head(x: 62, y: bodyY - 16, tilt: headTilt)

        case .normal:
            // Contact, lift, passing, opposite contact, recovery. The lifted paws
            // leave the ground instead of sliding sideways, unlike the tired gait.
            let bodyY = [22.0, 20, 22, 24, 23][frame]
            tail(CGPoint(x: 29, y: bodyY + 9),
                 CGPoint(x: [8.0, 9, 13, 12, 8][frame], y: [11.0, 7, 5, 8, 13][frame]),
                 CGPoint(x: 9, y: bodyY + 7), CGPoint(x: 5, y: 19))
            let legs: [[(Double, Double)]] = [
                [(28, 48), (19, 59), (42, 48), (49, 52), (62, 48), (56, 54), (78, 49), (85, 59)],
                [(30, 48), (28, 59), (44, 46), (52, 48), (69, 44), (78, 49), (75, 48), (78, 59)],
                [(35, 45), (44, 51), (40, 50), (37, 59), (72, 47), (83, 58), (70, 49), (65, 59)],
                [(42, 49), (49, 59), (32, 48), (23, 59), (65, 50), (59, 59), (75, 47), (82, 51)],
                [(37, 50), (41, 59), (34, 46), (40, 50), (61, 48), (53, 58), (75, 49), (81, 57)],
            ]
            for (leg, rootX) in [34.0, 43, 63, 70].enumerated() {
                let knee = legs[frame][leg * 2]
                let paw = legs[frame][leg * 2 + 1]
                stroke([CGPoint(x: rootX, y: bodyY + 14),
                        CGPoint(x: knee.0, y: knee.1), CGPoint(x: paw.0, y: paw.1)], width: 6.5)
            }
            ellipse(24, bodyY, 51, 23)
            head(x: 62, y: bodyY - 16, tilt: [-0.05, -0.08, 0, 0.06, 0][frame])

        case .tired:
            // Slow shuffle: pull a paw forward, sag, pause low, shift weight, recover.
            // A rounded back, drooping tail and bowed head distinguish every frame
            // from the upright normal walk, even without the orange color.
            let backY = [27.0, 30, 34, 32, 29][frame]
            tail(CGPoint(x: 29, y: backY + 15),
                 CGPoint(x: 8, y: [49.0, 52, 56, 54, 51][frame]),
                 CGPoint(x: 9, y: backY + 4), CGPoint(x: 17, y: 58))
            let legs: [[(Double, Double)]] = [
                [(28, 52), (24, 59), (42, 52), (47, 57), (62, 53), (56, 59), (78, 53), (83, 59)],
                [(33, 53), (38, 57), (39, 54), (35, 59), (69, 54), (74, 59), (76, 54), (80, 59)],
                [(32, 55), (28, 59), (43, 55), (46, 59), (65, 56), (60, 59), (78, 56), (83, 59)],
                [(29, 54), (23, 59), (42, 53), (47, 59), (64, 54), (58, 59), (78, 51), (84, 56)],
                [(29, 52), (25, 59), (42, 53), (47, 59), (65, 52), (70, 57), (77, 53), (82, 59)],
            ]
            for (leg, rootX) in [33.0, 43, 63, 73].enumerated() {
                let knee = legs[frame][leg * 2]
                let paw = legs[frame][leg * 2 + 1]
                stroke([CGPoint(x: rootX, y: 47), CGPoint(x: knee.0, y: knee.1),
                        CGPoint(x: paw.0, y: paw.1)], width: 6.5)
            }
            let back = CGMutablePath()
            back.move(to: CGPoint(x: 24, y: 48))
            back.addCurve(to: CGPoint(x: 75, y: 42),
                          control1: CGPoint(x: 21, y: backY - 7), control2: CGPoint(x: 51, y: backY - 3))
            back.addQuadCurve(to: CGPoint(x: 63, y: 54), control: CGPoint(x: 82, y: 54))
            back.addQuadCurve(to: CGPoint(x: 24, y: 48), control: CGPoint(x: 30, y: 59))
            context.addPath(back)
            context.fillPath()
            head(x: 62, y: [25.0, 29, 32, 30, 27][frame],
                 tilt: [0.16, 0.23, 0.30, 0.26, 0.20][frame], sleepy: true)

        case .sleeping:
            // Five quiet breaths: the back expands upward while the belly stays
            // grounded; the tucked head and wrapped tail settle as the cat exhales.
            let backY = [33.0, 29, 25, 27, 31][frame]
            ellipse(22, backY, 62, 59 - backY)
            tail(CGPoint(x: 32, y: backY + 7), CGPoint(x: [59.0, 60, 61, 60, 59][frame], y: 53),
                 CGPoint(x: 4, y: 47), CGPoint(x: 24, y: 61), width: 9)
            context.saveGState()
            context.setBlendMode(.clear)
            tail(CGPoint(x: 29, y: 44), CGPoint(x: 54, y: 51),
                 CGPoint(x: 22, y: 52), CGPoint(x: 43, y: 54), width: 2.5)
            context.restoreGState()
            head(x: [59.0, 58, 57, 58, 59][frame], y: [31.0, 30, 28, 29, 30][frame],
                 tilt: [0.30, 0.27, 0.23, 0.25, 0.29][frame], sleepy: true)

        case .unknown:
            // An upright, still waiting pose keeps missing data distinct from sleep.
            tail(CGPoint(x: 38, y: 53), CGPoint(x: 17, y: 36),
                 CGPoint(x: 12, y: 62), CGPoint(x: 9, y: 46))
            ellipse(31, 25, 37, 34)
            stroke([CGPoint(x: 43, y: 40), CGPoint(x: 43, y: 58)], width: 8)
            stroke([CGPoint(x: 58, y: 40), CGPoint(x: 58, y: 58)], width: 8)
            head(x: 35, y: 3, tilt: -0.16)
            // A small question mark reinforces the neutral waiting pose without color.
            tail(CGPoint(x: 76, y: 12), CGPoint(x: 81, y: 25),
                 CGPoint(x: 91, y: 1), CGPoint(x: 95, y: 20), width: 4)
            ellipse(79, 30, 4, 4)
        }
    }

    /// Explicit point and pixel sizes prevent MenuBarExtra from using oversized artwork.
    /// `frameIndex` は状態ごとのサイクルを `menuFrameCount` に量子化した番号。
    static func menuImage(for state: CharacterState, frameIndex: Int = 0, custom: NSImage? = nil) -> NSImage {
        let scale = 2.0
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 52, pixelsHigh: 44,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        let context = graphics.cgContext
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: menuSize.height)
        context.scaleBy(x: 1, y: -1)
        if let custom, let cgImage = custom.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let ratio = min(menuArtworkRect.width / Double(cgImage.width), menuArtworkRect.height / Double(cgImage.height))
            let size = CGSize(width: Double(cgImage.width) * ratio, height: Double(cgImage.height) * ratio)
            context.saveGState()
            context.translateBy(x: menuSize.width / 2, y: menuSize.height / 2)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
            context.restoreGState()
        } else {
            draw(in: context, rect: menuArtworkRect, state: state,
                 elapsed: menuFrameElapsed(for: state, frameIndex: frameIndex),
                 color: NSColor.black.cgColor, template: true)
        }
        bitmap.size = menuSize
        let image = NSImage(size: menuSize)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}
