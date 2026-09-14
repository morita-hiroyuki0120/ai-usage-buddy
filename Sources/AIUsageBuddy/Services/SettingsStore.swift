import Foundation
import Combine

/// アプリ設定の永続化。
public final class SettingsStore: ObservableObject, @unchecked Sendable {

    public static let shared = SettingsStore()

    @Published public var settings: AppSettings {
        didSet { persist() }
    }

    /// このストアが読み書きするコンテナディレクトリ（インストール状態判定に使う）。
    public let containerDirectory: URL
    private let fileURL: URL
    private let logger = AppLogger(category: "SettingsStore")

    public init(containerDirectory: URL? = nil) {
        let base = containerDirectory ?? AccountStore.defaultContainer()
        self.containerDirectory = base
        self.fileURL = base.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            var mutable = loaded
            let normalized = mutable.notificationThresholds.map(Self.normalizedNotificationThreshold)
            let needsThresholdMigration = normalized != mutable.notificationThresholds
            mutable.notificationThresholds = normalized
            let needsSchemaMigration = mutable.schemaVersion != AppSettings.currentSchemaVersion
            mutable.schemaVersion = AppSettings.currentSchemaVersion
            self.settings = mutable
            if needsThresholdMigration || needsSchemaMigration {
                // init 内の代入は didSet を発火しないため、移行結果を明示的に保存する
                persist()
            }
        } else {
            self.settings = AppSettings()
        }
    }

    /// しきい値を 5〜100 の 5 の倍数へ正規化する。
    /// 5 より小さい値は 5 へ、100 より大きい値は 100 へ切り詰め、
    /// その間は下側の 5 の倍数へ丸める（51 → 50、56 → 55、99 → 95）。
    private static func normalizedNotificationThreshold(_ value: Int) -> Int {
        let clamped = min(100, max(5, value))
        return (clamped / 5) * 5
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("failed to persist settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Convenience

    /// 通知しきい値を1つ更新する（値は 5〜100 の 5 の倍数へ正規化される）。
    /// AppSettings を値コピーして配列要素を書き換え、settings 全体を再代入する
    /// （ことで @Published の変更通知と didSet による永続化を確実に発生させる）。
    public func updateNotificationThreshold(at index: Int, to value: Int) {
        guard settings.notificationThresholds.indices.contains(index) else {
            return
        }

        var updatedSettings = settings
        updatedSettings.notificationThresholds[index] = Self.normalizedNotificationThreshold(value)
        settings = updatedSettings
    }

    /// グローバルショートカット2つをまとめて更新する（他の設定項目は保持）。
    public func updateShortcuts(show: HotKeySpec, refresh: HotKeySpec) {
        var updatedSettings = settings
        updatedSettings.showUsageShortcut = show
        updatedSettings.refreshShortcut = refresh
        settings = updatedSettings
    }

    /// 初回セットアップを完了扱いにする（スキップした場合も同じく再表示しない）。
    public func markOnboardingCompleted(version: Int) {
        guard !settings.onboardingCompleted || settings.onboardingVersion != version else { return }
        var updatedSettings = settings
        updatedSettings.onboardingCompleted = true
        updatedSettings.onboardingVersion = version
        settings = updatedSettings
    }

    public func displayLimit(for accountID: UUID) -> QuotaLimitKind {
        settings.displayLimit(for: accountID)
    }

    public func setDisplayLimit(_ limit: QuotaLimitKind, for accountID: UUID) {
        settings.displayLimitByAccount[accountID] = limit
    }
}
