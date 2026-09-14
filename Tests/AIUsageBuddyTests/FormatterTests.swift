import Foundation
import Testing
@testable import AIUsageBuddy

/// リセット日時表示・残り時間計算のテスト。
@Suite
struct FormatterTests {

    // MARK: - 残り時間

    @Test("残り時間（日本語）: 3時間12分")
    func remainingTimeJapanese() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(3 * 3600 + 12 * 60)
        #expect(UsageFormatter.remainingTime(from: now, to: reset, language: .japanese) == "3時間 12分")
    }

    @Test("残り時間（英語）: 3h 12m")
    func remainingTimeEnglish() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(3 * 3600 + 12 * 60)
        #expect(UsageFormatter.remainingTime(from: now, to: reset, language: .english) == "3h 12m")
    }

    @Test("残り時間（日単位・日本語）")
    func remainingTimeDaysJapanese() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(2 * 86400 + 5 * 3600 + 30 * 60)
        #expect(UsageFormatter.remainingTime(from: now, to: reset, language: .japanese) == "2日 5時間 30分")
    }

    @Test("残り時間が分のみの場合")
    func remainingTimeMinutesOnly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(45 * 60)
        #expect(UsageFormatter.remainingTime(from: now, to: reset, language: .japanese) == "45分")
        #expect(UsageFormatter.remainingTime(from: now, to: reset, language: .english) == "45m")
    }

    @Test("リセット済みの場合は0分にクランプ")
    func remainingTimeClampsToZeroAfterReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let past = now.addingTimeInterval(-600)
        #expect(UsageFormatter.remainingTime(from: now, to: past, language: .japanese) == "0分")
    }

    // MARK: - リセット日時（ローカル時刻）

    @Test("リセット日時は指定タイムゾーンで表記される")
    func resetDateTimeUsesSpecifiedTimeZone() {
        // 2026-09-11 03:22:34 UTC（検証時に公式から返った resetsAt = 1789096954 相当）
        let resetAt = Date(timeIntervalSince1970: 1_789_096_954)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let utc = TimeZone(identifier: "UTC")!

        let tokyoText = UsageFormatter.resetDateTime(resetAt, timeZone: tokyo, locale: Locale(identifier: "ja_JP"))
        let utcText = UsageFormatter.resetDateTime(resetAt, timeZone: utc, locale: Locale(identifier: "en_US_POSIX"))

        // タイムゾーンごとに時刻表記が変わること（UTC 03:22 / JST 12:22）
        #expect(tokyoText.contains("12:22"), "JST表記には12:22が含まれる: \(tokyoText)")
        #expect(utcText.contains("3:22"), "UTC表記には3:22が含まれる: \(utcText)")
    }

    @Test("リセット日時は空文字にならない")
    func resetDateTimeIsNotEmpty() {
        let text = UsageFormatter.resetDateTime(Date(), timeZone: .current, locale: Locale(identifier: "ja_JP"))
        #expect(!text.isEmpty)
    }

    // MARK: - 残量の正規化

    @Test("残量は0〜100にクランプされる")
    func quotaWindowClampsPercent() {
        let over = QuotaWindow(kind: .fiveHour, remainingPercent: 150, resetAt: nil, fetchedAt: Date(), state: .fresh)
        #expect(over.remainingPercent == 100)

        let negative = QuotaWindow(kind: .weekly, remainingPercent: -20, resetAt: nil, fetchedAt: Date(), state: .fresh)
        #expect(negative.remainingPercent == 0)
    }
}
