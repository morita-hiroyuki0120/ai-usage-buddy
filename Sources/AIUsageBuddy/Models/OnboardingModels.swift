import Foundation

/// 初回セットアップのステップ（5段階）。
public enum OnboardingStep: Int, CaseIterable, Sendable, Equatable {
    /// 歓迎
    case welcome
    /// 公式アカウント接続（任意・スキップ可能）
    case connect
    /// 通知許可（任意）
    case notifications
    /// ログイン時自動起動（任意・明示確認）
    case loginItem
    /// 使い方
    case usageGuide

    public var titleKey: String { "onboarding.step.\(rawValue).title" }
    public var bodyKey: String { "onboarding.step.\(rawValue).body" }
}

/// 初回セットアップの内容バージョン。ステップ構成を変えたら上げる。
public enum OnboardingFlow {
    public static let currentVersion = 1
}

/// 新規インストールか既存インストールかの判定。
/// AppModel が既定アカウントを自動作成する前に呼ぶことで、
/// 「既存ユーザーに初回セットアップを表示しない」を実現する。
public enum InstallDetector {

    public enum InstallStatus: Equatable, Sendable {
        /// 初回起動（永続化ファイルが一切無い）。
        case freshInstall
        /// 既存ユーザー（何らかの永続化ファイルが存在する）。
        case existingInstall
    }

    /// コンテナ内に設定・アカウント・スナップショットのいずれかがあれば既存扱い。
    /// （初回起動でも既定アカウントの自動作成で accounts.json が即座に作られるため、
    ///  判定は自動作成より前に行う必要がある）
    public static func detect(fileManager: FileManager = .default, container: URL) -> InstallStatus {
        let markers = ["settings.json", "accounts.json", "snapshots.json"]
        let hasExistingData = markers.contains { name in
            fileManager.fileExists(atPath: container.appendingPathComponent(name).path)
        }
        return hasExistingData ? .existingInstall : .freshInstall
    }
}
