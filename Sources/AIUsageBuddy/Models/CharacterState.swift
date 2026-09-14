import Foundation

/// キャラクターの状態。
public enum CharacterState: String, CaseIterable, Sendable {
    /// 元気（70〜100%）
    case energetic
    /// 通常（30〜69%）
    case normal
    /// 疲れている（1〜29%）
    case tired
    /// 睡眠／停止（0%）
    case sleeping
    /// データ未取得（中立状態＋「接続が必要」）
    case unknown

    public var localizedNameKey: String {
        switch self {
        case .energetic: return "character.state.energetic"
        case .normal: return "character.state.normal"
        case .tired: return "character.state.tired"
        case .sleeping: return "character.state.sleeping"
        case .unknown: return "character.state.unknown"
        }
    }
}

/// 残量からキャラクター状態を求める状態機械。
/// ヒステリシス幅は5ポイント。
///
/// - 元気から通常へ: 65%未満
/// - 通常から元気へ: 70%以上
/// - 通常から疲労へ: 29%以下
/// - 疲労から通常へ: 34%以上
/// - 疲労から睡眠へ: 0%以下
/// - 睡眠から疲労へ: 5%以上
public struct CharacterStateMachine: Sendable {
    public init() {}

    /// 残量からバンドを求める（初期状態の決定用）。
    /// - 70〜100: energetic
    /// - 30〜69: normal
    /// - 1〜29: tired
    /// - 0: sleeping
    public static func band(forPercent percent: Int) -> CharacterState {
        switch percent {
        case ..<1: return .sleeping
        case 1...29: return .tired
        case 30...69: return .normal
        default: return .energetic
        }
    }

    /// データ未取得時の状態。
    public static let noDataState: CharacterState = .unknown

    /// 現在状態と残量から次の状態を求める。percent が nil の場合は unknown へ遷移する。
    /// 残量が急変した場合も段階的に遷移させるため、不動点に到達するまで遷移を適用する。
    public func next(current: CharacterState, percent: Int?) -> CharacterState {
        guard let percent else { return .unknown }
        var state = current
        if current == .unknown {
            // 未取得から復帰する場合はバンドから直接決める
            return Self.band(forPercent: percent)
        }
        // 段階遷移を不動点まで適用（最大状態数分で収束する）
        for _ in 0..<CharacterState.allCases.count {
            let next = step(current: state, percent: percent)
            if next == state { break }
            state = next
        }
        return state
    }

    /// 1ステップ分の遷移。
    func step(current: CharacterState, percent: Int) -> CharacterState {
        switch current {
        case .energetic:
            // 元気から通常へ: 65%未満
            return percent < 65 ? .normal : .energetic
        case .normal:
            // 通常から疲労へ: 29%以下（疲労を優先して判定）
            if percent <= 29 { return .tired }
            // 通常から元気へ: 70%以上
            return percent >= 70 ? .energetic : .normal
        case .tired:
            // 疲労から睡眠へ: 0%以下
            if percent <= 0 { return .sleeping }
            // 疲労から通常へ: 34%以上
            return percent >= 34 ? .normal : .tired
        case .sleeping:
            // 睡眠から疲労へ: 5%以上
            return percent >= 5 ? .tired : .sleeping
        case .unknown:
            return Self.band(forPercent: percent)
        }
    }
}
