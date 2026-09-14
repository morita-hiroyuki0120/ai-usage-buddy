import Foundation
import Testing
@testable import AIUsageBuddy

/// SnapshotStore の永続化・通知キー管理のテスト。
@Suite
struct SnapshotStoreTests {

    private func makeStore() -> (SnapshotStore, URL) {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AIUsageBuddyStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return (SnapshotStore(containerDirectory: container), container)
    }

    @Test("公式値の取得成功で手動補正は解除される")
    func officialSnapshotClearsManualOverrides() {
        let (store, _) = makeStore()
        let accountID = UUID()
        let now = Date()

        store.setManualOverride(accountID: accountID, kind: .fiveHour, percent: 30, now: now)
        #expect(store.hasManualOverride(accountID: accountID))

        let official = UsageSnapshot(
            accountID: accountID,
            fiveHour: QuotaWindow(kind: .fiveHour, remainingPercent: 60, resetAt: now.addingTimeInterval(3600), fetchedAt: now, state: .fresh),
            weekly: QuotaWindow(kind: .weekly, remainingPercent: 70, resetAt: now.addingTimeInterval(86400), fetchedAt: now, state: .fresh),
            fetchedAt: now
        )
        store.storeOfficialSnapshot(official)
        #expect(!store.hasManualOverride(accountID: accountID))
        #expect(store.snapshot(for: accountID)?.fiveHour?.remainingPercent == 60)
    }

    @Test("手動補正は再読み込み後も保持される")
    func manualOverridePreservedAcrossReload() {
        let (store, container) = makeStore()
        let accountID = UUID()
        store.setManualOverride(accountID: accountID, kind: .weekly, percent: 42)

        let reloaded = SnapshotStore(containerDirectory: container)
        #expect(reloaded.manualOverride(accountID: accountID, kind: .weekly)?.percent == 42)
    }

    @Test("リセット済み枠の通知キーは破棄され再通知可能になる")
    func notifiedKeyPrunedAfterReset() {
        let (store, _) = makeStore()
        let accountID = UUID()
        let pastReset = Date().addingTimeInterval(-3600)
        let futureReset = Date().addingTimeInterval(3600)

        let oldKey = SnapshotStore.notificationKey(accountID: accountID, kind: .fiveHour, threshold: 20, resetAt: pastReset)
        let newKey = SnapshotStore.notificationKey(accountID: accountID, kind: .fiveHour, threshold: 20, resetAt: futureReset)

        store.markNotified(key: oldKey)
        store.markNotified(key: newKey)

        #expect(!store.hasNotified(key: oldKey), "リセット済み枠のキーは破棄")
        #expect(store.hasNotified(key: newKey), "未来の枠のキーは保持")
    }

    @Test("stale マークで値は保持される")
    func markStaleKeepsValues() {
        let (store, _) = makeStore()
        let accountID = UUID()
        let now = Date()
        let official = UsageSnapshot(
            accountID: accountID,
            fiveHour: QuotaWindow(kind: .fiveHour, remainingPercent: 55, resetAt: now.addingTimeInterval(1800), fetchedAt: now, state: .fresh),
            weekly: nil,
            fetchedAt: now
        )
        store.storeOfficialSnapshot(official)
        store.markStale(accountID: accountID, kind: .timeout, detail: "timeout")

        let snapshot = store.snapshot(for: accountID)
        #expect(snapshot?.fiveHour?.remainingPercent == 55, "値は前回のまま")
        #expect(snapshot?.fiveHour?.state == .stale)
        #expect(snapshot?.lastErrorMessage == "timeout")
        #expect(snapshot?.lastErrorKind == .timeout, "エラー種別が記録される")
    }
}
