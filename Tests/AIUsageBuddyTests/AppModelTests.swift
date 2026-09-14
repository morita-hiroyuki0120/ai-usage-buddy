import Foundation
import Testing
@testable import AIUsageBuddy

/// stale処理・手動補正からの復帰・複数アカウント・表示リミット保持のテスト。
@Suite
@MainActor
struct AppModelTests {

    private func makeSnapshot(
        accountID: UUID,
        fiveHourRemaining: Int,
        weeklyRemaining: Int,
        resetInterval: TimeInterval = 3600,
        fetchedAt: Date = Date()
    ) -> UsageSnapshot {
        UsageSnapshot(
            accountID: accountID,
            fiveHour: QuotaWindow(
                kind: .fiveHour,
                remainingPercent: fiveHourRemaining,
                resetAt: Date().addingTimeInterval(resetInterval),
                fetchedAt: fetchedAt,
                state: .fresh
            ),
            weekly: QuotaWindow(
                kind: .weekly,
                remainingPercent: weeklyRemaining,
                resetAt: Date().addingTimeInterval(resetInterval * 24),
                fetchedAt: fetchedAt,
                state: .fresh
            ),
            fetchedAt: fetchedAt
        )
    }

    // MARK: - stale データ処理

    @Test("取得失敗時は前回値を stale 表示で保持")
    func fetchFailureKeepsPreviousValueAsStale() async {
        let account = Account(displayName: "テスト", homeKind: .defaultHome)
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 40, weeklyRemaining: 60)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])

        // 1) まず公式取得に成功させて前回値をストアへ入れる
        await env.model.refreshAll(sendNotifications: false)
        #expect(env.model.snapshots[account.id]?.fiveHour?.state == .fresh)

        // 2) 取得が失敗する状態にする
        env.provider.setFetchError(CodexClientError.timeout(method: "account/rateLimits/read"))
        await env.model.refreshAll(sendNotifications: false)

        let snapshot = env.model.snapshots[account.id]
        #expect(snapshot != nil, "前回値が残る")
        #expect(snapshot?.fiveHour?.remainingPercent == 40, "残量は前回値を維持")
        #expect(snapshot?.fiveHour?.state == .stale, "状態は stale になる")
        #expect(snapshot?.lastErrorMessage != nil)
    }

    @Test("経過時間による stale 判定")
    func staleDetectionByAge() {
        let old = Date().addingTimeInterval(-UsageSnapshot.staleThreshold - 60)
        let snapshot = makeSnapshot(accountID: UUID(), fiveHourRemaining: 50, weeklyRemaining: 50, fetchedAt: old)
        #expect(snapshot.isStale(), "閾値超過で stale")

        let recent = Date().addingTimeInterval(-30)
        let fresh = makeSnapshot(accountID: UUID(), fiveHourRemaining: 50, weeklyRemaining: 50, fetchedAt: recent)
        #expect(!fresh.isStale(), "最近の取得は stale でない")
    }

    // MARK: - 手動補正 → 公式値への復帰

    @Test("手動補正は公式取得成功時に自動解除される")
    func manualOverrideAppliesAndClearsOnOfficialSuccess() async {
        let account = Account(displayName: "テスト", homeKind: .defaultHome)
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 35, weeklyRemaining: 55)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])

        // 1) 自動取得が失敗する
        env.provider.setFetchError(CodexClientError.timeout(method: "account/rateLimits/read"))
        await env.model.refreshAll(sendNotifications: false)

        // 2) 手動補正を入力
        env.model.setManualOverride(accountID: account.id, kind: .fiveHour, percent: 12)
        #expect(env.model.snapshots[account.id]?.fiveHour?.remainingPercent == 12)
        #expect(env.model.snapshots[account.id]?.fiveHour?.state == .manual, "手動補正中の表示")
        #expect(env.model.snapshotStore.hasManualOverride(accountID: account.id))

        // 3) 公式取得が成功すると手動補正は自動解除され公式値へ戻る
        env.provider.setFetchError(nil)
        let official = makeSnapshot(accountID: account.id, fiveHourRemaining: 77, weeklyRemaining: 88)
        env.provider.setSnapshot(official)
        await env.model.refreshAll(sendNotifications: false)

        let recovered = env.model.snapshots[account.id]
        #expect(recovered?.fiveHour?.remainingPercent == 77, "公式値に戻る")
        #expect(recovered?.fiveHour?.state == .fresh)
        #expect(!env.model.snapshotStore.hasManualOverride(accountID: account.id), "手動補正は解除済み")
    }

    @Test("手動補正の入力は0〜100にクランプ")
    func manualOverrideClampedToRange() {
        let account = Account(displayName: "テスト", homeKind: .defaultHome)
        let env = TestEnvironment.make(accounts: [account])

        env.model.setManualOverride(accountID: account.id, kind: .fiveHour, percent: 130)
        #expect(env.model.snapshotStore.manualOverride(accountID: account.id, kind: .fiveHour)?.percent == 100)

        env.model.setManualOverride(accountID: account.id, kind: .fiveHour, percent: -5)
        #expect(env.model.snapshotStore.manualOverride(accountID: account.id, kind: .fiveHour)?.percent == 0)
    }

    // MARK: - 複数アカウント切り替え

    @Test("アカウント切り替えで表示残量と状態が変わる")
    func accountSwitchingUpdatesDisplayedPercent() async {
        let accountA = Account(displayName: "アカウントA", homeKind: .defaultHome)
        let accountB = Account(displayName: "アカウントB", homeKind: .managed)
        let snapshotA = makeSnapshot(accountID: accountA.id, fiveHourRemaining: 80, weeklyRemaining: 90)
        let snapshotB = makeSnapshot(accountID: accountB.id, fiveHourRemaining: 15, weeklyRemaining: 40)
        let env = TestEnvironment.make(
            accounts: [accountA, accountB],
            snapshots: [snapshotA, snapshotB]
        )
        try? env.model.accountStore.saveAccounts([accountA, accountB])

        // Aを選択 → 元気
        env.model.selectAccount(accountA.id)
        await env.model.refreshAll(sendNotifications: false)
        #expect(env.model.displayedPercent == 80)
        #expect(env.model.characterState == .energetic)

        // Bを選択 → 疲労（表示リミットは5時間枠のまま）
        env.model.selectAccount(accountB.id)
        env.model.recomputeDisplayedState()
        #expect(env.model.displayedPercent == 15)
        #expect(env.model.characterState == .tired)
    }

    // MARK: - 5時間／週間表示リミットの保持

    @Test("アカウントごとの表示リミットは永続化される")
    func displayLimitPerAccountPersisted() async {
        let accountA = Account(displayName: "A", homeKind: .defaultHome)
        let accountB = Account(displayName: "B", homeKind: .managed)
        let env = TestEnvironment.make(accounts: [accountA, accountB])
        try? env.model.accountStore.saveAccounts([accountA, accountB])

        // デフォルトは5時間枠
        #expect(env.model.settingsStore.displayLimit(for: accountA.id) == .fiveHour)

        // アカウントごとに異なるリミットを設定
        env.model.setDisplayLimit(.weekly, for: accountA.id)
        env.model.setDisplayLimit(.fiveHour, for: accountB.id)
        #expect(env.model.settingsStore.displayLimit(for: accountA.id) == .weekly)
        #expect(env.model.settingsStore.displayLimit(for: accountB.id) == .fiveHour)

        // 設定の永続化（新しい SettingsStore で同じファイルから読み戻す）
        let reloaded = SettingsStore(containerDirectory: env.container)
        #expect(reloaded.settings.displayLimit(for: accountA.id) == .weekly)
        #expect(reloaded.settings.displayLimit(for: accountB.id) == .fiveHour)
    }

    @Test("キャラクター状態は表示リミット基準で変わる")
    func characterStateFollowsDisplayedLimit() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        // 5時間枠は残75%（元気）、週間枠は残8%（疲労）
        let snapshot = makeSnapshot(accountID: account.id, fiveHourRemaining: 75, weeklyRemaining: 8)
        let env = TestEnvironment.make(accounts: [account], snapshots: [snapshot])
        try? env.model.accountStore.saveAccounts([account])

        await env.model.refreshAll(sendNotifications: false)
        #expect(env.model.characterState == .energetic, "5時間枠基準では元気")

        env.model.setDisplayLimit(.weekly, for: account.id)
        #expect(env.model.characterState == .tired, "週間枠基準では疲労に変わる")
        #expect(env.model.displayedPercent == 8)
    }
}
