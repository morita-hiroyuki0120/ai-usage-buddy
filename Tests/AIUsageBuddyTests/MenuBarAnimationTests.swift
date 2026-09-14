import AppKit
import Testing
@testable import AIUsageBuddy

/// メニューバーアイコンのフレームアニメーション（量子化・キャッシュ・クロック）のテスト。
/// staticキャッシュ（MenuBarIconCache）を持つため、テスト間でバンドルを差し替え・復元する。
@Suite
@MainActor
struct MenuBarAnimationTests {

    // MARK: - Helpers

    private func pngData(of image: NSImage) throws -> Data {
        let rep = try #require(image.representations.first as? NSBitmapImageRep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// 指定ファイル名（拡張子なし）→グレー値のPNGを置いた擬似バンドルを作る。
    private func makeBundle(withTintedFiles files: [String: CGFloat]) throws -> Bundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarAnimationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, gray) in files {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 160,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = try #require(NSGraphicsContext(bitmapImageRep: rep)).cgContext
            context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 160))
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: dir.appendingPathComponent("\(name).png"))
        }
        return try #require(Bundle(path: dir.path))
    }

    // MARK: - フレーム量子化

    @Test("unknownは1フレームで常に0、他状態は5フレームに量子化される")
    func frameQuantization() {
        #expect(CatDrawing.menuFrameCount(for: .unknown) == 1)
        for state in CharacterState.allCases where state != .unknown {
            #expect(CatDrawing.menuFrameCount(for: state) == 5, "\(state): フレーム数が足りない")
        }
        #expect(CatDrawing.menuFrameIndex(for: .unknown, elapsed: 100) == 0)

        // energetic: 0.7秒を5枚のポーズで表示する
        #expect(CatDrawing.menuFrameCount(for: .energetic) == 5)
        #expect(CatDrawing.menuFrameIndex(for: .energetic, elapsed: 0.35) == 2)
        // サイクルをまたぐとループする
        #expect(CatDrawing.menuFrameIndex(for: .energetic, elapsed: 0.7 + 0.14) == 1)
        // フレーム経過時間はサイクル内に収まる
        let count = CatDrawing.menuFrameCount(for: .tired)
        let duration = CatDrawing.cycleDuration(for: .tired)
        for frame in 0..<count {
            let elapsed = CatDrawing.menuFrameElapsed(for: .tired, frameIndex: frame)
            #expect(elapsed >= 0 && elapsed < duration)
        }
    }

    @Test("ベクター描画は5枚の異なる絵をコマ内で保持し、1周後に戻る")
    func flipbookHoldsEachPose() throws {
        func render(_ state: CharacterState, _ elapsed: Double) throws -> Data {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 128,
                                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                                       bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap)).cgContext
            CatDrawing.draw(in: context, rect: CGRect(x: 0, y: 0, width: 200, height: 128),
                            state: state, elapsed: elapsed, color: CGColor(gray: 0, alpha: 1), template: true)
            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
        for state in CharacterState.allCases where state != .unknown {
            let duration = CatDrawing.cycleDuration(for: state)
            let interval = duration / 5
            var poses = Set<Data>()
            for frame in 0..<5 {
                let start = Double(frame) * interval
                let early = try render(state, start + interval * 0.1)
                let late = try render(state, start + interval * 0.9)
                #expect(early == late, "コマの途中で絵が変わっている")
                poses.insert(early)
            }
            #expect(poses.count == 5, "5枚の異なるポーズが必要")
            #expect(try render(state, interval * 0.1) == render(state, duration + interval * 0.1))
        }
    }

    // MARK: - キャッシュ

    @Test("animated状態では異なるフレームの画像が異なる")
    func distinctFrames() throws {
        defer { MenuBarIconCache.resetForTesting(bundle: .module) }
        MenuBarIconCache.resetForTesting(bundle: .module)

        let cases: [(CharacterState, Int)] = [
            (.energetic, 3), (.normal, 3), (.tired, 3), (.sleeping, 3),
        ]
        for (state, otherFrame) in cases {
            let frame0 = try pngData(of: MenuBarIconCache.image(for: state, frameIndex: 0))
            let frameN = try pngData(of: MenuBarIconCache.image(for: state, frameIndex: otherFrame))
            #expect(frame0 != frameN, "\(state): フレーム0と\(otherFrame)が同じ画像")
        }
    }

    @Test("同じstate・同じframeの画像はキャッシュを返す")
    func cachedInstanceReuse() {
        defer { MenuBarIconCache.resetForTesting(bundle: .module) }
        MenuBarIconCache.resetForTesting(bundle: .module)

        for state in CharacterState.allCases {
            let first = MenuBarIconCache.image(for: state, frameIndex: 0)
            #expect(first === MenuBarIconCache.image(for: state, frameIndex: 0),
                    "\(state): 同一キーで再描画されている")
        }
        let normal2 = MenuBarIconCache.image(for: .normal, frameIndex: 2)
        #expect(normal2 === MenuBarIconCache.image(for: .normal, frameIndex: 2))
    }

    @Test("全フレームが26×22pt・52×44px・テンプレート・透明余白を維持する")
    func frameSizeAndMargins() throws {
        defer { MenuBarIconCache.resetForTesting(bundle: .module) }
        MenuBarIconCache.resetForTesting(bundle: .module)

        for state in CharacterState.allCases {
            let frameCount = CatDrawing.menuFrameCount(for: state)
            for frame in 0..<max(frameCount, 1) {
                let image = MenuBarIconCache.image(for: state, frameIndex: frame)
                #expect(image.size == CatDrawing.menuSize, "\(state) frame\(frame): サイズ不正")
                #expect(image.isTemplate, "\(state) frame\(frame): テンプレートでない")
                let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
                #expect(bitmap.pixelsWide == 52 && bitmap.pixelsHigh == 44)
                var visiblePixels = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let alpha = try #require(bitmap.colorAt(x: x, y: y)).alphaComponent
                        if y < 6 || y >= 38 {
                            #expect(alpha == 0, "\(state) frame\(frame): 余白にはみ出し (\(x), \(y))")
                        }
                        if alpha > 0 { visiblePixels += 1 }
                    }
                }
                #expect(visiblePixels > 60, "\(state) frame\(frame): 空のアイコン")
            }
        }
    }

    // MARK: - アニメーション要否

    @Test("unknownは常に静止する")
    func unknownIsStatic() throws {
        defer { MenuBarIconCache.resetForTesting(bundle: .module) }
        MenuBarIconCache.resetForTesting(bundle: .module)

        #expect(!MenuBarIconCache.animates(.unknown))
        #expect(MenuBarIconCache.image(for: .unknown, frameIndex: 7)
                === MenuBarIconCache.image(for: .unknown, frameIndex: 0))

        let clock = MenuBarAnimationClock()
        clock.update(state: .unknown, motionPolicy: .animated)
        clock.advanceCycleStartForTesting(by: 10)
        clock.tickForTesting()
        #expect(clock.frameIndex == 0)
    }

    @Test("Reduce Motion有効時はフレームが変化しない")
    func reduceMotionFreezesFrames() {
        defer { MenuBarIconCache.resetForTesting(bundle: .module) }
        MenuBarIconCache.resetForTesting(bundle: .module)

        let clock = MenuBarAnimationClock()
        clock.update(state: .normal, motionPolicy: .staticOnly)
        clock.advanceCycleStartForTesting(by: 1.0)
        for _ in 0..<5 { clock.tickForTesting() }
        #expect(clock.frameIndex == 0)

        // 実行中にReduce Motionが解除されたらアニメーションが再開する
        clock.update(state: .normal, motionPolicy: .animated)
        clock.advanceCycleStartForTesting(by: 1.0)
        clock.tickForTesting()
        #expect(clock.frameIndex > 0)
    }

    @Test("状態変更時にフレーム番号がリセットされる")
    func stateChangeResetsFrame() {
        defer { MenuBarIconCache.resetForTesting(bundle: .module) }
        MenuBarIconCache.resetForTesting(bundle: .module)

        let clock = MenuBarAnimationClock()
        clock.update(state: .energetic, motionPolicy: .animated)
        clock.advanceCycleStartForTesting(by: 0.5)
        clock.tickForTesting()
        #expect(clock.frameIndex > 0, "アニメーションが進んでいない")

        clock.update(state: .normal, motionPolicy: .animated)
        #expect(clock.frameIndex == 0, "状態変更でフレーム0に戻っていない")

        // 同一状態の再更新ではリセットしない（サイクル継続）
        clock.advanceCycleStartForTesting(by: 1.0)
        clock.tickForTesting()
        let advanced = clock.frameIndex
        #expect(advanced > 0)
        clock.update(state: .normal, motionPolicy: .animated)
        clock.tickForTesting()
        #expect(clock.frameIndex == advanced, "同一状態の再更新でサイクルがリセットされた")
    }

    // MARK: - カスタムアートワーク

    @Test("custom単一PNGは静止表示される")
    func customSingleImageIsStatic() throws {
        let bundle = try makeBundle(withTintedFiles: ["character-normal": 0.5])
        defer { MenuBarIconCache.resetForTesting(bundle: .module) }
        MenuBarIconCache.resetForTesting(bundle: bundle)

        #expect(!MenuBarIconCache.animates(.normal), "単一PNG差し替えなのにアニメーションする")
        // frameIndexを変えても同一インスタンス（静止フレーム0）
        #expect(MenuBarIconCache.image(for: .normal, frameIndex: 4)
                === MenuBarIconCache.image(for: .normal, frameIndex: 0))

        let clock = MenuBarAnimationClock()
        clock.update(state: .normal, motionPolicy: .animated)
        clock.advanceCycleStartForTesting(by: 10)
        clock.tickForTesting()
        #expect(clock.frameIndex == 0, "単一PNG差し替え時にクロックが動いている")
    }

    @Test("個別フレームPNGがある場合はフレームが切り替わる")
    func customFrameSetsAnimate() throws {
        let bundle = try makeBundle(withTintedFiles: [
            "character-normal-frame-0": 0.0,
            "character-normal-frame-1": 0.5,
            "character-normal-frame-2": 1.0,
        ])
        defer { MenuBarIconCache.resetForTesting(bundle: .module) }
        MenuBarIconCache.resetForTesting(bundle: bundle)

        let frames = try #require(CharacterArtwork.customFrames(for: .normal, bundle: bundle))
        #expect(frames.count == 3)

        #expect(MenuBarIconCache.animates(.normal))

        // フレームごとに異なる画像
        let frame0 = try pngData(of: MenuBarIconCache.image(for: .normal, frameIndex: 0))
        let frame1 = try pngData(of: MenuBarIconCache.image(for: .normal, frameIndex: 1))
        #expect(frame0 != frame1, "フレーム素材が切り替わっていない")

        // インデックスはループする
        #expect(MenuBarIconCache.image(for: .normal, frameIndex: 3)
                === MenuBarIconCache.image(for: .normal, frameIndex: 0))

        // 素材差し替え画像もサイズ・余白の枠を守る
        let image = MenuBarIconCache.image(for: .normal, frameIndex: 1)
        #expect(image.size == CatDrawing.menuSize)
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = try #require(bitmap.colorAt(x: x, y: y)).alphaComponent
                if y < 6 || y >= 38 {
                    #expect(alpha == 0, "フレーム素材が余白にはみ出し (\(x), \(y))")
                }
            }
        }

        let clock = MenuBarAnimationClock()
        clock.update(state: .normal, motionPolicy: .animated)
        clock.advanceCycleStartForTesting(by: 1.0)
        clock.tickForTesting()
        #expect(clock.frameIndex > 0)
    }
}
