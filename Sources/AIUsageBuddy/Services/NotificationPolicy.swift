import Foundation

/// 低残量通知の判定ロジック（テスト可能な純粋関数群）。
/// - 登録済み全アカウントを監視
/// - 通知設定はアプリ全体で共通
/// - 各アカウント・各リミット・各しきい値につき、リセット枠ごとに1回だけ通知
/// - stale データ・手動補正中からは通知しない
public enum NotificationPolicy {

    /// 通知が必要かどうかの判定結果。
    public struct Decision: Equatable, Sendable {
        public let accountID: UUID
        public let kind: QuotaLimitKind
        public let threshold: Int
        public let key: String
        public let accountDisplayName: String
        public let remainingPercent: Int
    }

    /// スナップショットと既送信キーから、送信すべき通知のリストを求める。
    public static func pendingNotifications(
        accounts: [Account],
        snapshots: [UUID: UsageSnapshot],
        thresholds: [Int],
        enabled: Bool,
        alreadyNotified: (String) -> Bool,
        now: Date = Date()
    ) -> [Decision] {
        guard enabled else { return [] }
        var decisions: [Decision] = []

        for account in accounts {
            guard let snapshot = snapshots[account.id] else { continue }
            // stale なスナップショットからは通知しない
            if snapshot.isStale(now: now) { continue }
            // 直近の取得が失敗している（エラーを記録している）場合は通知しない
            if snapshot.lastErrorKind != nil { continue }

            for kind in QuotaLimitKind.allCases {
                guard let window = snapshot.window(for: kind) else { continue }
                // 手動補正中の値からは通知しない
                guard window.state != .manual else { continue }
                // 取得失敗で stale 化したウィンドウからは通知しない
                // （fetchedAt が新しくても、前回値を表示しているだけの場合がある）
                guard window.state != .stale else { continue }
                // リセット済みウィンドウは通知しない
                if let resetAt = window.resetAt, resetAt <= now { continue }

                for threshold in thresholds.sorted() where threshold > 0 {
                    guard window.remainingPercent <= threshold else { continue }
                    let key = SnapshotStore.notificationKey(
                        accountID: account.id,
                        kind: kind,
                        threshold: threshold,
                        resetAt: window.resetAt
                    )
                    guard !alreadyNotified(key) else { continue }
                    // より高いしきい値で既に通知済みの場合は、低いしきい値のみ追加で通知する
                    decisions.append(
                        Decision(
                            accountID: account.id,
                            kind: kind,
                            threshold: threshold,
                            key: key,
                            accountDisplayName: account.displayName,
                            remainingPercent: window.remainingPercent
                        )
                    )
                }
            }
        }
        return decisions
    }
}
