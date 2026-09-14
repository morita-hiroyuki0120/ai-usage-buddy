import Foundation
import Testing
@testable import AIUsageBuddy

/// 通知重複抑制・リセット後の再送のテスト。
@Suite
struct NotificationPolicyTests {

    private func makeSnapshot(
        accountID: UUID,
        fiveHourRemaining: Int,
        weeklyRemaining: Int,
        fiveHourReset: Date,
        weeklyReset: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            accountID: accountID,
            fiveHour: QuotaWindow(
                kind: .fiveHour,
                remainingPercent: fiveHourRemaining,
                resetAt: fiveHourReset,
                fetchedAt: Date(),
                state: .fresh
            ),
            weekly: QuotaWindow(
                kind: .weekly,
                remainingPercent: weeklyRemaining,
                resetAt: weeklyReset,
                fetchedAt: Date(),
                state: .fresh
            ),
            fetchedAt: Date()
        )
    }

    // MARK: - 基本動作

    @Test("しきい値を下回ると通知が必要になる")
    func notificationFiresWhenBelowThreshold() {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let reset = Date().addingTimeInterval(3600)
        let snapshot = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 15,
            weeklyRemaining: 50,
            fiveHourReset: reset,
            weeklyReset: reset
        )
        let decisions = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: snapshot],
            thresholds: [20, 10],
            enabled: true,
            alreadyNotified: { _ in false }
        )
        // 15% はしきい値20を下回るが10は下回らない → 1件
        #expect(decisions.count == 1)
        #expect(decisions.first?.threshold == 20)
        #expect(decisions.first?.kind == .fiveHour)
        #expect(decisions.first?.remainingPercent == 15)
    }

    // MARK: - 重複抑制

    @Test("同一リセット枠では1回だけ通知")
    func duplicateSuppressedPerResetWindow() {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let reset = Date().addingTimeInterval(3600)
        let snapshot = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 15,
            weeklyRemaining: 50,
            fiveHourReset: reset,
            weeklyReset: reset
        )

        var notifiedKeys: Set<String> = []
        let first = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: snapshot],
            thresholds: [20],
            enabled: true,
            alreadyNotified: { notifiedKeys.contains($0) }
        )
        #expect(first.count == 1)
        notifiedKeys.formUnion(first.map(\.key))

        // 同じウィンドウ内で再判定 → 通知されない
        let second = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: snapshot],
            thresholds: [20],
            enabled: true,
            alreadyNotified: { notifiedKeys.contains($0) }
        )
        #expect(second.isEmpty, "同一リセット枠では1回だけ")

        // 値がしきい値を上下しても同じウィンドウなら再送しない
        let recovered = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 25,
            weeklyRemaining: 50,
            fiveHourReset: reset,
            weeklyReset: reset
        )
        let third = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: recovered],
            thresholds: [20],
            enabled: true,
            alreadyNotified: { notifiedKeys.contains($0) }
        )
        #expect(third.isEmpty)
    }

    // MARK: - リセット後の再送

    @Test("リセット後の新しい枠では再通知される")
    func notifiesAgainAfterWindowReset() {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let oldReset = Date().addingTimeInterval(-60) // すでにリセットされた枠
        let newReset = Date().addingTimeInterval(3600)

        let beforeReset = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 15,
            weeklyRemaining: 50,
            fiveHourReset: oldReset,
            weeklyReset: newReset
        )
        var notifiedKeys: Set<String> = []
        // 便宜的に古いキーを「送信済み」として登録しておく
        notifiedKeys.insert(SnapshotStore.notificationKey(accountID: account.id, kind: .fiveHour, threshold: 20, resetAt: oldReset))

        let decisions = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: beforeReset],
            thresholds: [20],
            enabled: true,
            alreadyNotified: { notifiedKeys.contains($0) }
        )
        #expect(decisions.isEmpty, "リセット済みウィンドウからは通知しない")

        // 新しいウィンドウで再び低残量になった → 再通知される
        let afterReset = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 8,
            weeklyRemaining: 50,
            fiveHourReset: newReset,
            weeklyReset: newReset
        )
        let newDecisions = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: afterReset],
            thresholds: [20, 10],
            enabled: true,
            alreadyNotified: { notifiedKeys.contains($0) }
        )
        #expect(newDecisions.count == 2, "新しい枠では20%と10%の両方が通知される")
    }

    // MARK: - stale・手動補正からの抑制

    @Test("staleデータからは通知しない")
    func noNotificationFromStaleData() {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let staleTime = Date().addingTimeInterval(-UsageSnapshot.staleThreshold - 120)
        var snapshot = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 5,
            weeklyRemaining: 50,
            fiveHourReset: Date().addingTimeInterval(3600),
            weeklyReset: Date().addingTimeInterval(86400)
        )
        snapshot.fetchedAt = staleTime
        snapshot.fiveHour?.state = .stale
        #expect(snapshot.isStale())

        let decisions = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: snapshot],
            thresholds: [20, 10],
            enabled: true,
            alreadyNotified: { _ in false }
        )
        #expect(decisions.isEmpty, "staleデータからは通知しない")
    }

    @Test("手動補正中のリミットからは通知しない")
    func noNotificationFromManualOverride() {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        var snapshot = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 5,
            weeklyRemaining: 50,
            fiveHourReset: Date().addingTimeInterval(3600),
            weeklyReset: Date().addingTimeInterval(86400)
        )
        snapshot.fiveHour?.state = .manual

        let decisions = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: snapshot],
            thresholds: [20, 10],
            enabled: true,
            alreadyNotified: { _ in false }
        )
        #expect(decisions.allSatisfy { $0.kind != .fiveHour }, "手動補正中のリミットからは通知しない")
    }

    // MARK: - 通知オフ

    @Test("通知オフなら何も生成しない")
    func disabledNotificationsProduceNone() {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let snapshot = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 5,
            weeklyRemaining: 5,
            fiveHourReset: Date().addingTimeInterval(3600),
            weeklyReset: Date().addingTimeInterval(86400)
        )
        let decisions = NotificationPolicy.pendingNotifications(
            accounts: [account],
            snapshots: [account.id: snapshot],
            thresholds: [20, 10],
            enabled: false,
            alreadyNotified: { _ in false }
        )
        #expect(decisions.isEmpty)
    }

    // MARK: - 複数アカウント

    @Test("登録済み全アカウントを監視する")
    func allRegisteredAccountsMonitored() {
        let accountA = Account(displayName: "A", homeKind: .defaultHome)
        let accountB = Account(displayName: "B", homeKind: .managed)
        let reset = Date().addingTimeInterval(3600)
        let snapshots: [UUID: UsageSnapshot] = [
            accountA.id: makeSnapshot(accountID: accountA.id, fiveHourRemaining: 8, weeklyRemaining: 90, fiveHourReset: reset, weeklyReset: reset),
            accountB.id: makeSnapshot(accountID: accountB.id, fiveHourRemaining: 60, weeklyRemaining: 12, fiveHourReset: reset, weeklyReset: reset),
        ]
        let decisions = NotificationPolicy.pendingNotifications(
            accounts: [accountA, accountB],
            snapshots: snapshots,
            thresholds: [20, 10],
            enabled: true,
            alreadyNotified: { _ in false }
        )
        // A: 5時間枠 8% → 20と10の2件 / B: 週間枠 12% → 20の1件
        #expect(decisions.count == 3)
        #expect(decisions.contains { $0.accountID == accountA.id && $0.kind == .fiveHour && $0.threshold == 20 })
        #expect(decisions.contains { $0.accountID == accountA.id && $0.kind == .fiveHour && $0.threshold == 10 })
        #expect(decisions.contains { $0.accountID == accountB.id && $0.kind == .weekly && $0.threshold == 20 })
        // 通知にアカウント名が含まれる
        #expect(decisions.contains { $0.accountDisplayName == "A" })
    }
}
