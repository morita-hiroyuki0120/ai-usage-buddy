import SwiftUI
import AppKit

/// メニューバー用キャラクターアイコンのキャッシュ。
/// キーは (状態, フレーム番号)。同一キーには同一NSImageインスタンスを返し、
/// 異なるフレームは別画像として生成する。メニューバーの明暗に追従させるため
/// すべてテンプレート（モノクロ）画像。
@MainActor
enum MenuBarIconCache {
    struct CacheKey: Hashable {
        let state: CharacterState
        let frameIndex: Int
    }

    /// 差し替えアセットの探索バンドル（テストで差し替え可能）。
    static var bundle: Bundle = .module

    private static var cache: [CacheKey: NSImage] = [:]
    private static var customFrameSets: [CharacterState: [NSImage]] = [:]

    /// この状態がメニューバーでアニメーションするか。
    /// - unknown は常に静止
    /// - カスタム単一PNG差し替え（フレーム素材なし）は静止
    /// - フレーム素材 PNG またはベクター描画は動く
    static func animates(_ state: CharacterState) -> Bool {
        guard state != .unknown else { return false }
        if customFrames(for: state) != nil { return true }
        if CharacterArtwork.customImage(for: state, bundle: bundle) != nil { return false }
        return true
    }

    static func image(for state: CharacterState, frameIndex: Int = 0) -> NSImage {
        let key = CacheKey(state: state, frameIndex: normalizedFrameIndex(for: state, frameIndex: frameIndex))
        if let cached = cache[key] { return cached }

        let image: NSImage
        if let frames = customFrames(for: state) {
            // フレーム素材: インデックスをループさせる
            image = CatDrawing.menuImage(for: state, custom: frames[key.frameIndex % frames.count])
        } else if let single = CharacterArtwork.customImage(for: state, bundle: bundle) {
            // 単一PNG差し替えは常に同じ静止フレーム
            image = CatDrawing.menuImage(for: state, custom: single)
        } else {
            image = CatDrawing.menuImage(for: state, frameIndex: key.frameIndex)
        }
        cache[key] = image
        return image
    }

    /// 素材の種類に応じてキャッシュキーを正規化する。
    /// - unknown / 単一PNG差し替え → 常に 0（静止）
    /// - フレーム素材 → 0..<count に丸める
    /// - ベクター描画 → そのまま（クロックがサイクル内に量子化して渡す）
    private static func normalizedFrameIndex(for state: CharacterState, frameIndex: Int) -> Int {
        if state == .unknown { return 0 }
        if let frames = customFrames(for: state) { return frameIndex % frames.count }
        if CharacterArtwork.customImage(for: state, bundle: bundle) != nil { return 0 }
        return frameIndex
    }

    private static func customFrames(for state: CharacterState) -> [NSImage]? {
        if let cached = customFrameSets[state] { return cached }
        guard let frames = CharacterArtwork.customFrames(for: state, bundle: bundle) else { return nil }
        customFrameSets[state] = frames
        return frames
    }

    /// テスト用: キャッシュを空にし、探索バンドルを差し替える。
    static func resetForTesting(bundle newBundle: Bundle? = nil) {
        cache.removeAll()
        customFrameSets.removeAll()
        if let newBundle { bundle = newBundle }
    }
}

/// メニューバーアイコンのアニメーション駆動クロック。
/// Timer で一定間隔（4〜8fps帯）ごとにフレーム番号を更新する。
/// 次の場合はタイマーを停止して静止フレーム（0）を表示する:
/// - 状態が unknown
/// - Reduce Motion 有効（motionPolicy == .staticOnly）
/// - カスタム単一PNG差し替え（フレーム素材なし）
@MainActor
final class MenuBarAnimationClock: ObservableObject {
    /// 値が実際に変わった時だけ objectWillChange を送る（@Published は同値代入でも
    /// 通知してしまうため、labelのbody評価内で update を呼ぶと再評価循環が起きる）。
    private var _frameIndex: Int = 0 {
        willSet {
            if newValue != _frameIndex { objectWillChange.send() }
        }
    }

    var frameIndex: Int { _frameIndex }

    private var timer: Timer?
    private var state: CharacterState = .unknown
    private var motionPolicy: MotionPolicy = .animated
    private var cycleStart = Date()

    /// 状態またはモーション設定を更新する。状態が変わったらフレーム0からやり直す。
    func update(state newState: CharacterState, motionPolicy policy: MotionPolicy) {
        let stateChanged = newState != state
        state = newState
        motionPolicy = policy
        if stateChanged {
            cycleStart = Date()
            _frameIndex = 0
        }
        restartTimerIfNeeded()
    }

    /// テスト用: 即座に1フレーム進める。
    func tickForTesting() {
        advanceFrame()
    }

    /// テスト用: サイクル開始時刻を過去へずらして経過時間を進めたことにする。
    func advanceCycleStartForTesting(by interval: TimeInterval) {
        cycleStart.addTimeInterval(-interval)
    }

    private var shouldAnimate: Bool {
        motionPolicy == .animated && MenuBarIconCache.animates(state)
    }

    private func restartTimerIfNeeded() {
        if shouldAnimate {
            guard timer == nil else { return }
            let newTimer = Timer(timeInterval: 1.0 / CatDrawing.menuAnimationFPS, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.advanceFrame()
                }
            }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        } else {
            timer?.invalidate()
            timer = nil
            _frameIndex = 0
        }
    }

    private func advanceFrame() {
        guard shouldAnimate else {
            _frameIndex = 0
            return
        }
        let elapsed = -cycleStart.timeIntervalSinceNow
        let next = CatDrawing.menuFrameIndex(for: state, elapsed: elapsed)
        if next != _frameIndex {
            _frameIndex = next
        }
    }

    deinit {
        timer?.invalidate()
    }
}

/// メニューバーに表示するキャラクターのみのラベル。
/// - 数値・残量バーは出さない
/// - モノクロ（テンプレート画像）でmacOS標準メニューバーになじむサイズ
/// - `MenuBarAnimationClock` が低負荷のフレーム更新を担う（SwiftUIの暗黙アニメーション非依存）
struct MenuBarCharacterLabel: View {
    let state: CharacterState
    let motionPolicy: MotionPolicy

    @StateObject private var clock = MenuBarAnimationClock()

    var body: some View {
        // MenuBarExtra の label では onAppear/onChange が確実に発火しないため、
        // body評価時にクロックを同期更新する（update は同一状態に対して冪等で、
        // frameIndex 更新による再評価でもサイクルはリセットしない）。
        let _ = clock.update(state: state, motionPolicy: motionPolicy)
        return Image(nsImage: MenuBarIconCache.image(for: state, frameIndex: clock.frameIndex))
            .frame(width: CatDrawing.menuSize.width, height: CatDrawing.menuSize.height)
            .accessibilityLabel(L(state.localizedNameKey))
            .accessibilityIdentifier("menubar-character")
    }
}
