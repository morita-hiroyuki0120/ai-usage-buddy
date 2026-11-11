import Foundation

/// App Review 用「サンプルデータ」表示で切り替える残量シナリオ。
/// 実アカウント・通信・保存領域には一切関与しない、表示専用のデータ。
public enum SampleScenario: String, CaseIterable, Sendable {
    /// 余裕あり（猫: 元気／通常）
    case plenty
    /// 低残量（猫: 疲れている）
    case low
    /// ほぼ枯渇（猫: 睡眠／疲れている）
    case nearlyDepleted

    public var localizedNameKey: String {
        switch self {
        case .plenty: return "sample.scenario.plenty"
        case .low: return "sample.scenario.low"
        case .nearlyDepleted: return "sample.scenario.nearlyDepleted"
        }
    }
}

/// サンプルアカウントとサンプル利用枠の決定的な生成。
/// 値は (シナリオ, 現在時刻) だけで決まり、乱数・通信・ファイルを使わない。
public enum SampleData {

    /// サンプルアカウントの固定ID（実アカウントのIDとは衝突しない固定値）。
    public static let firstAccountID = UUID(uuidString: "5A3D1E00-0000-4000-8000-000000000001")!
    public static let secondAccountID = UUID(uuidString: "5A3D1E00-0000-4000-8000-000000000002")!

    public static var accountIDs: [UUID] { [firstAccountID, secondAccountID] }

    /// 表示名は呼び出し側（ローカライズ済み）から受け取る。メール・プランなど公式識別情報は持たせない。
    public static func accounts(firstName: String, secondName: String) -> [Account] {
        [
            Account(id: firstAccountID, displayName: firstName, homeKind: .managed),
            Account(id: secondAccountID, displayName: secondName, homeKind: .managed),
        ]
    }

    private struct Entry {
        let fiveHourPercent: Int
        let fiveHourResetIn: TimeInterval
        let weeklyPercent: Int
        let weeklyResetIn: TimeInterval
    }

    private static let hour: TimeInterval = 3600

    private static func entry(for accountID: UUID, scenario: SampleScenario) -> Entry {
        let isFirst = accountID == firstAccountID
        switch (scenario, isFirst) {
        case (.plenty, true):
            return Entry(fiveHourPercent: 82, fiveHourResetIn: 4 * hour + 20 * 60, weeklyPercent: 64, weeklyResetIn: 5 * 24 * hour + 3 * hour)
        case (.plenty, false):
            return Entry(fiveHourPercent: 55, fiveHourResetIn: 2 * hour + 5 * 60, weeklyPercent: 71, weeklyResetIn: 3 * 24 * hour + 8 * hour)
        case (.low, true):
            return Entry(fiveHourPercent: 24, fiveHourResetIn: 1 * hour + 35 * 60, weeklyPercent: 18, weeklyResetIn: 2 * 24 * hour + 6 * hour)
        case (.low, false):
            return Entry(fiveHourPercent: 62, fiveHourResetIn: 3 * hour + 10 * 60, weeklyPercent: 33, weeklyResetIn: 4 * 24 * hour + 2 * hour)
        case (.nearlyDepleted, true):
            return Entry(fiveHourPercent: 0, fiveHourResetIn: 2 * hour + 50 * 60, weeklyPercent: 6, weeklyResetIn: 1 * 24 * hour + 2 * hour)
        case (.nearlyDepleted, false):
            return Entry(fiveHourPercent: 38, fiveHourResetIn: 45 * 60, weeklyPercent: 12, weeklyResetIn: 6 * 24 * hour + 5 * hour)
        }
    }

    /// 指定シナリオのサンプルスナップショット（サンプルアカウント全員分）。
    /// `snapshot.fetchedAt` は nil のまま（「最終取得」を実通信の結果に見せない）。
    public static func snapshots(scenario: SampleScenario, now: Date) -> [UUID: UsageSnapshot] {
        var result: [UUID: UsageSnapshot] = [:]
        for id in accountIDs {
            let e = entry(for: id, scenario: scenario)
            result[id] = UsageSnapshot(
                accountID: id,
                fiveHour: QuotaWindow(
                    kind: .fiveHour,
                    remainingPercent: e.fiveHourPercent,
                    resetAt: now.addingTimeInterval(e.fiveHourResetIn),
                    fetchedAt: now,
                    state: .fresh
                ),
                weekly: QuotaWindow(
                    kind: .weekly,
                    remainingPercent: e.weeklyPercent,
                    resetAt: now.addingTimeInterval(e.weeklyResetIn),
                    fetchedAt: now,
                    state: .fresh
                )
            )
        }
        return result
    }
}
