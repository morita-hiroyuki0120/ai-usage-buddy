import SwiftUI
import AppKit

/// キャラクターの描画モード（Reduce Motion 対応）。
/// テスト可能な純粋関数として分離する。
public enum MotionPolicy: Equatable, Sendable {
    case animated
    case staticOnly

    /// Reduce Motion の設定から描画モードを求める。
    public static func resolve(reduceMotionEnabled: Bool) -> MotionPolicy {
        reduceMotionEnabled ? .staticOnly : .animated
    }
}

/// キャラクターのアセット解決。
/// バンドル内に差し替え画像（character-energetic 等）があればそれを使い、
/// 無ければSwiftUI描画にフォールバックする構成。
public enum CharacterArtwork {

    static let assetNames: [CharacterState: String] = [
        .energetic: "character-energetic",
        .normal: "character-normal",
        .tired: "character-tired",
        .sleeping: "character-sleeping",
        .unknown: "character-unknown",
    ]

    /// 差し替え画像が存在するか。
    static func hasCustomArtwork(for state: CharacterState, bundle: Bundle) -> Bool {
        guard let name = assetNames[state] else { return false }
        return bundle.url(forResource: name, withExtension: "png") != nil
    }

    /// 差し替え画像をテンプレート（モノクロ）画像として返す。
    static func customImage(for state: CharacterState, bundle: Bundle) -> NSImage? {
        guard let name = assetNames[state],
              let url = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    /// 差し替えアニメーションフレーム（`character-<state>-frame-0.png`, `-frame-1.png`, ...）を
    /// 連続して存在する分だけ返す。frame-0 が無ければ nil（単一PNGのみ＝静止扱い）。
    static func customFrames(for state: CharacterState, bundle: Bundle) -> [NSImage]? {
        guard let baseName = assetNames[state] else { return nil }
        var frames: [NSImage] = []
        var index = 0
        while let url = bundle.url(forResource: "\(baseName)-frame-\(index)", withExtension: "png"),
              let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            frames.append(image)
            index += 1
        }
        return frames.isEmpty ? nil : frames
    }
}

/// 目の状態（瞬きアニメーション用）。
enum EyeState {
    case open
    case closed
}

/// キャラクター（小さなAI猫）のSwiftUI描画。
/// メニューバーでは輪郭をモノクロ（1色）で描き、ポップオーバーでは状態色で描く。
struct CatFace: View {
    let state: CharacterState
    let monochrome: Bool
    var eyes: EyeState = .open

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let bodyColor = monochrome ? Color.primary : paletteBody
            let featureColor = monochrome ? Color.primary : Color.white

            ZStack {
                Group {
                    if monochrome {
                        CatHeadShape()
                            .stroke(bodyColor, lineWidth: max(size * 0.085, 1.2))
                    } else {
                        CatHeadShape()
                            .fill(bodyColor.opacity(0.94))
                    }
                }
                catFeatures(color: featureColor, size: size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func catFeatures(color: Color, size: CGFloat) -> some View {
        let eyeWidth = size * 0.10
        let eyeHeight = eyes == .closed ? size * 0.02 : eyeSize(for: state, size: size)
        let eyeY = size * 0.02

        switch state {
        case .sleeping:
            ForEach([-1, 1], id: \.self) { side in
                Capsule()
                    .fill(color)
                    .frame(width: size * 0.14, height: size * 0.025)
                    .offset(x: side * size * 0.15, y: eyeY)
            }
        case .energetic:
            ForEach([-1, 1], id: \.self) { side in
                DiamondShape()
                    .fill(color)
                    .frame(width: eyeWidth * 1.5, height: eyeHeight * 1.6)
                    .offset(x: side * size * 0.15, y: eyeY)
            }
        default:
            ForEach([-1, 1], id: \.self) { side in
                Capsule()
                    .fill(color)
                    .frame(width: eyeWidth, height: eyeHeight)
                    .offset(x: side * size * 0.15, y: eyeY)
            }
        }

        DiamondShape()
            .fill(monochrome ? color : paletteAccent)
            .frame(width: size * 0.055, height: size * 0.045)
            .offset(y: size * 0.105)

        switch state {
        case .energetic:
            ArcShape()
                .stroke(color, lineWidth: size * 0.035)
                .frame(width: size * 0.22, height: size * 0.10)
                .offset(y: size * 0.17)
        case .tired:
            TiltedLineShape()
                .stroke(color, lineWidth: size * 0.03)
                .frame(width: size * 0.18, height: size * 0.05)
                .offset(y: size * 0.17)
        case .sleeping:
            Circle()
                .fill(color)
                .frame(width: size * 0.04, height: size * 0.04)
                .offset(x: size * 0.08, y: size * 0.17)
        case .normal:
            Capsule()
                .fill(color)
                .frame(width: size * 0.16, height: size * 0.03)
                .offset(y: size * 0.17)
        case .unknown:
            Capsule()
                .fill(color.opacity(0.65))
                .frame(width: size * 0.16, height: size * 0.02)
                .offset(y: size * 0.17)
        }
    }

    private func eyeSize(for state: CharacterState, size: CGFloat) -> CGFloat {
        switch state {
        case .energetic: size * 0.16
        case .normal: size * 0.12
        case .tired: size * 0.08
        default: size * 0.10
        }
    }

    private var paletteBody: Color {
        switch state {
        case .energetic: return Color(nsColor: NSColor.systemTeal)
        case .normal: return Color(nsColor: NSColor.systemBlue)
        case .tired: return Color(nsColor: NSColor.systemOrange)
        case .sleeping: return Color(nsColor: NSColor.systemGray)
        case .unknown: return Color(nsColor: NSColor.systemGray)
        }
    }

    private var paletteAccent: Color {
        switch state {
        case .energetic: return Color(nsColor: NSColor.systemYellow)
        default: return Color(nsColor: NSColor.controlAccentColor)
        }
    }

    private var accessibilityText: String {
        L(state.localizedNameKey)
    }
}

/// キャラクターの旧ロボット描画。差し替え画像との互換性のため残す。
struct RobotFace: View {
    let state: CharacterState
    let monochrome: Bool
    var eyes: EyeState = .open
    /// 待機モーションの位相（0〜1）。Reduce Motion 時は固定。
    var idlePhase: Double = 0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let bodyColor = monochrome ? Color.primary : paletteBody
            let accentColor = monochrome ? Color.primary : paletteAccent

            ZStack {
                // 頭部（角丸矩形）
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(bodyColor.opacity(monochrome ? 1.0 : 0.9))
                    .frame(width: size * 0.82, height: size * 0.66)
                    .offset(y: size * (monochrome ? 0.0 : 0.02))

                // アンテナ
                Capsule()
                    .fill(bodyColor)
                    .frame(width: size * 0.07, height: size * 0.18)
                    .offset(x: 0, y: -size * 0.44)
                Circle()
                    .fill(accentColor)
                    .frame(width: size * 0.14, height: size * 0.14)
                    .offset(x: 0, y: -size * 0.55)

                // 顔（ディスプレイ窓）
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .fill(monochrome ? Color.primary.opacity(0.15) : Color.black.opacity(0.25))
                    .frame(width: size * 0.62, height: size * 0.3)
                    .offset(y: monochrome ? 0 : size * 0.02)

                // 目
                eyeShapes(color: monochrome ? Color.primary : Color.white, size: size)

                // 口（状態ごとの表情）
                mouth(color: monochrome ? Color.primary : Color.white, size: size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func eyeShapes(color: Color, size: CGFloat) -> some View {
        let eyeWidth: CGFloat = size * 0.10
        let eyeHeight: CGFloat = eyes == .closed ? size * 0.02 : eyeSize(for: state, size: size)
        let eyeY: CGFloat = monochrome ? 0 : size * 0.02
        switch state {
        case .sleeping:
            // 閉じた目（横線）
            ForEach([-1, 1], id: \.self) { side in
                Capsule()
                    .fill(color)
                    .frame(width: size * 0.14, height: size * 0.025)
                    .offset(x: side * size * 0.15, y: eyeY)
            }
        case .energetic:
            // 星形に近い菱形の目
            ForEach([-1, 1], id: \.self) { side in
                DiamondShape()
                    .fill(color)
                    .frame(width: eyeWidth * 1.5, height: eyeHeight * 1.6)
                    .offset(x: side * size * 0.15, y: eyeY)
            }
        default:
            ForEach([-1, 1], id: \.self) { side in
                Capsule()
                    .fill(color)
                    .frame(width: eyeWidth, height: eyeHeight)
                    .offset(x: side * size * 0.15, y: eyeY)
            }
        }
    }

    @ViewBuilder
    private func mouth(color: Color, size: CGFloat) -> some View {
        let y: CGFloat = (monochrome ? 0 : size * 0.02) + size * 0.12
        switch state {
        case .energetic:
            // 笑った口（弧）
            ArcShape()
                .stroke(color, lineWidth: size * 0.035)
                .frame(width: size * 0.22, height: size * 0.10)
                .offset(y: y)
        case .normal:
            Capsule()
                .fill(color)
                .frame(width: size * 0.16, height: size * 0.03)
                .offset(y: y)
        case .tired:
            // 波形の口（簡易的に斜め線）
            TiltedLineShape()
                .stroke(color, lineWidth: size * 0.03)
                .frame(width: size * 0.18, height: size * 0.05)
                .offset(y: y)
        case .sleeping:
            // 「zzz」の代わりに小さい丸
            Circle()
                .fill(color)
                .frame(width: size * 0.04, height: size * 0.04)
                .offset(x: size * 0.08, y: y)
        case .unknown:
            Capsule()
                .fill(color.opacity(0.6))
                .frame(width: size * 0.16, height: size * 0.02)
                .offset(y: y)
        }
    }

    private func eyeSize(for state: CharacterState, size: CGFloat) -> CGFloat {
        switch state {
        case .energetic: size * 0.16
        case .normal: size * 0.12
        case .tired: size * 0.08
        default: size * 0.10
        }
    }

    private var paletteBody: Color {
        switch state {
        case .energetic: return Color(nsColor: NSColor.systemTeal)
        case .normal: return Color(nsColor: NSColor.systemBlue)
        case .tired: return Color(nsColor: NSColor.systemOrange)
        case .sleeping: return Color(nsColor: NSColor.systemGray)
        case .unknown: return Color(nsColor: NSColor.systemGray)
        }
    }

    private var paletteAccent: Color {
        switch state {
        case .energetic: return Color(nsColor: NSColor.systemYellow)
        default: return Color(nsColor: NSColor.controlAccentColor)
        }
    }

    private var accessibilityText: String {
        L(state.localizedNameKey)
    }
}

/// ライト／ダークモードで見える色を解決する（テスト可能）。
public enum CharacterPalette {
    /// 表示コンテキストごとのベース色の濃度。
    public static func bodyOpacity(for colorScheme: ColorScheme, highContrast: Bool) -> Double {
        if highContrast {
            return 1.0
        }
        switch colorScheme {
        case .light: return 0.9
        case .dark: return 0.85
        @unknown default: return 0.9
        }
    }
}

// MARK: - Shapes

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct CatHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        // 左耳、頭頂部、右耳を一筆で結び、猫らしい輪郭を作る。
        path.move(to: CGPoint(x: width * 0.08, y: height * 0.08))
        path.addLine(to: CGPoint(x: width * 0.37, y: height * 0.23))
        path.addCurve(
            to: CGPoint(x: width * 0.63, y: height * 0.23),
            control1: CGPoint(x: width * 0.43, y: height * 0.12),
            control2: CGPoint(x: width * 0.57, y: height * 0.12)
        )
        path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.08))
        path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.62))
        path.addCurve(
            to: CGPoint(x: width * 0.16, y: height * 0.62),
            control1: CGPoint(x: width * 0.80, y: height * 0.97),
            control2: CGPoint(x: width * 0.20, y: height * 0.97)
        )
        path.closeSubpath()
        return path
    }
}

struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

struct TiltedLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
