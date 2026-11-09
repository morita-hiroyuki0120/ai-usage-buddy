import Foundation
import Testing
@testable import AIUsageBuddy

private actor DelayedPendingLoginClient: PendingLoginClient {
    private let notificationGate = AsyncTestGate()
    private let accountReadGate = AsyncTestGate()
    private let firstStopGate: AsyncTestGate?
    private let lateStopGate = AsyncTestGate()
    private var notificationContinuation: AsyncStream<ServerNotification>.Continuation?
    private var stopCount = 0

    init(delayFirstStop: Bool = false) {
        firstStopGate = delayFirstStop ? AsyncTestGate() : nil
    }

    func start() async throws {}

    func startLogin() async throws -> LoginStartResult {
        LoginStartResult(type: "chatgpt", authUrl: "https://example.invalid/", loginId: "fixture")
    }

    func notifications() -> AsyncStream<ServerNotification> {
        let stream = AsyncStream<ServerNotification>.makeStream()
        notificationContinuation = stream.continuation
        Task { await notificationGate.pause() }
        return stream.stream
    }

    func readAccount() async throws -> GetAccountResponse {
        await accountReadGate.pause()
        return GetAccountResponse(account: nil, requiresOpenaiAuth: true)
    }

    func stop() async {
        stopCount += 1
        notificationContinuation?.finish()
        if stopCount == 1, let firstStopGate {
            await firstStopGate.pause()
        } else if stopCount == 2 {
            await lateStopGate.pause()
        }
    }

    func waitForNotificationSubscription() async {
        await notificationGate.waitForArrival()
        await notificationGate.release()
    }

    func sendSuccessfulCompletion() {
        notificationContinuation?.yield(ServerNotification(
            method: "account/login/completed",
            params: .dictionary(["success": .bool(true)])
        ))
    }

    func waitForAccountRead() async {
        await accountReadGate.waitForArrival()
    }

    func releaseAccountRead() async {
        await accountReadGate.release()
    }

    func waitForFirstStop() async {
        await firstStopGate?.waitForArrival()
    }

    func releaseFirstStop() async {
        await firstStopGate?.release()
    }

    func waitForLateStop() async {
        await lateStopGate.waitForArrival()
    }

    func releaseLateStop() async {
        await lateStopGate.release()
    }
}

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

    @Test("アカウント削除時に利用枠・補正・通知キー・表示設定を永続ストアから消去")
    func deleteAccountClearsPersistedAccountData() async throws {
        let account = Account(displayName: "削除対象", homeKind: .managed)
        let env = TestEnvironment.make(accounts: [account])
        defer { try? FileManager.default.removeItem(at: env.container) }
        let managedHome = try env.model.accountStore.prepareManagedHome(for: account.id)
        let managedFixture = managedHome.appendingPathComponent("fixture.txt")
        try Data("test-only fixture".utf8).write(to: managedFixture)
        let now = Date()
        env.model.snapshotStore.storeOfficialSnapshot(
            makeSnapshot(accountID: account.id, fiveHourRemaining: 45, weeklyRemaining: 65, fetchedAt: now)
        )
        env.model.snapshotStore.setManualOverride(accountID: account.id, kind: .fiveHour, percent: 20, now: now)
        let notificationKey = SnapshotStore.notificationKey(
            accountID: account.id,
            kind: .weekly,
            threshold: 20,
            resetAt: now.addingTimeInterval(3600)
        )
        env.model.snapshotStore.markNotified(key: notificationKey)
        var settings = env.model.settingsStore.settings
        settings.displayLimitByAccount[account.id] = .weekly
        env.model.settingsStore.settings = settings

        await env.model.deleteAccount(account.id)

        let reloadedStore = SnapshotStore(containerDirectory: env.container)
        let reloadedSettings = SettingsStore(containerDirectory: env.container)
        #expect(reloadedStore.snapshot(for: account.id) == nil)
        #expect(!reloadedStore.hasManualOverride(accountID: account.id))
        #expect(!reloadedStore.hasNotified(key: notificationKey))
        #expect(reloadedSettings.settings.displayLimitByAccount[account.id] == nil)
        #expect(env.model.accounts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: managedHome.path))
        #expect(env.model.accountDeletionErrorMessage == nil)
    }

    @Test("managed home削除失敗ではアカウント・利用データ・設定を保持し安全なエラーを表示")
    func deleteAccountFailurePreservesAccountData() async throws {
        let account = Account(displayName: "保持対象", homeKind: .managed)
        let initialSnapshot = makeSnapshot(
            accountID: account.id,
            fiveHourRemaining: 45,
            weeklyRemaining: 65
        )
        let env = TestEnvironment.make(accounts: [account], snapshots: [initialSnapshot])
        defer { try? FileManager.default.removeItem(at: env.container) }

        let home = try env.model.accountStore.prepareManagedHome(for: account.id)
        let homesDirectory = home.deletingLastPathComponent()
        let marker = home.appendingPathComponent("fixture.txt")
        try Data("test-only fixture".utf8).write(to: marker)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: homesDirectory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: home.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: homesDirectory.path)
        }

        let now = Date()
        env.model.snapshotStore.setManualOverride(accountID: account.id, kind: .fiveHour, percent: 20, now: now)
        let notificationKey = SnapshotStore.notificationKey(
            accountID: account.id,
            kind: .weekly,
            threshold: 20,
            resetAt: now.addingTimeInterval(3600)
        )
        env.model.snapshotStore.markNotified(key: notificationKey)
        var settings = env.model.settingsStore.settings
        settings.displayLimitByAccount[account.id] = .weekly
        settings.selectedAccountID = account.id
        env.model.settingsStore.settings = settings

        await env.model.deleteAccount(account.id)

        let reloadedAccounts = try env.model.accountStore.loadAccounts()
        let reloadedStore = SnapshotStore(containerDirectory: env.container)
        let reloadedSettings = SettingsStore(containerDirectory: env.container)
        #expect(reloadedAccounts.map(\.id) == [account.id])
        #expect(reloadedStore.snapshot(for: account.id) != nil)
        #expect(reloadedStore.manualOverride(accountID: account.id, kind: .fiveHour)?.percent == 20)
        #expect(reloadedStore.hasNotified(key: notificationKey))
        #expect(reloadedSettings.settings.displayLimitByAccount[account.id] == .weekly)
        #expect(reloadedSettings.settings.selectedAccountID == account.id)
        #expect(env.model.accounts.map(\.id) == [account.id])
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(env.model.accountDeletionErrorMessage == L("settings.delete.failure"))
        #expect(!(env.model.accountDeletionErrorMessage ?? "").contains(env.container.path))
    }

    @Test("managed home symlinkがHomes外を指す場合は削除せず拒否")
    func deleteManagedHomeSymlinkEscapeFailsClosed() async throws {
        let account = Account(displayName: "symlink fixture", homeKind: .managed)
        let env = TestEnvironment.make(accounts: [account])
        defer { try? FileManager.default.removeItem(at: env.container) }
        let home = env.model.accountStore.managedHomeURL(for: account.id)
        try FileManager.default.createDirectory(
            at: home.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let externalFixture = env.container.appendingPathComponent("outside-managed-home", isDirectory: true)
        try FileManager.default.createDirectory(at: externalFixture, withIntermediateDirectories: true)
        let marker = externalFixture.appendingPathComponent("fixture.txt")
        try Data("test-only fixture".utf8).write(to: marker)
        try FileManager.default.createSymbolicLink(at: home, withDestinationURL: externalFixture)

        await env.model.deleteAccount(account.id)

        #expect(try env.model.accountStore.loadAccounts().map(\.id) == [account.id])
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(env.model.accountDeletionErrorMessage == L("settings.delete.failure"))
    }

    @Test("default-home account削除ではmanaged-homeのfixtureを削除しない")
    func deleteDefaultHomeAccountDoesNotRemoveManagedHomePath() async throws {
        let account = Account(displayName: "default home", homeKind: .defaultHome)
        let env = TestEnvironment.make(accounts: [account])
        defer { try? FileManager.default.removeItem(at: env.container) }
        let homeFixture = env.model.accountStore.managedHomeURL(for: account.id)
        try FileManager.default.createDirectory(at: homeFixture, withIntermediateDirectories: true)
        let marker = homeFixture.appendingPathComponent("fixture.txt")
        try Data("test-only fixture".utf8).write(to: marker)

        await env.model.deleteAccount(account.id)

        #expect(env.model.accounts.isEmpty)
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("削除中に遅れて返ったアカウント一覧で削除済みIDを復活させない")
    func delayedAccountListDoesNotResurrectDeletedAccount() async throws {
        let account = Account(displayName: "削除対象", homeKind: .managed)
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 5, weeklyRemaining: 8)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])
        defer { try? FileManager.default.removeItem(at: env.container) }
        var settings = env.model.settingsStore.settings
        settings.notificationsEnabled = true
        settings.notificationThresholds = [20]
        env.model.settingsStore.settings = settings

        let gate = AsyncTestGate()
        env.provider.setAccountsGate(gate)
        let refresh = Task { await env.model.refreshAll(sendNotifications: true) }
        await gate.waitForArrival()

        await env.model.deleteAccount(account.id)
        await gate.release()
        await refresh.value

        let storedAccounts = try env.model.accountStore.loadAccounts()
        let storedSnapshots = SnapshotStore(containerDirectory: env.container)
        #expect(storedAccounts.isEmpty)
        #expect(env.model.accounts.isEmpty)
        #expect(storedSnapshots.snapshot(for: account.id) == nil)
        #expect(!env.spy.sentNotifications.contains(where: { $0.accountID == account.id }))
    }

    @Test("利用枠取得await中の削除後にsnapshot・補正・通知状態を再永続化しない")
    func delayedSnapshotDoesNotRestoreDeletedAccountData() async throws {
        let account = Account(displayName: "削除対象", homeKind: .managed)
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 5, weeklyRemaining: 8)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])
        defer { try? FileManager.default.removeItem(at: env.container) }
        var settings = env.model.settingsStore.settings
        settings.notificationsEnabled = true
        settings.notificationThresholds = [20]
        settings.displayLimitByAccount[account.id] = .weekly
        env.model.settingsStore.settings = settings
        let now = Date()
        env.model.snapshotStore.storeOfficialSnapshot(initial)
        env.model.snapshotStore.setManualOverride(accountID: account.id, kind: .fiveHour, percent: 12, now: now)
        let notificationKey = SnapshotStore.notificationKey(
            accountID: account.id,
            kind: .weekly,
            threshold: 20,
            resetAt: now.addingTimeInterval(3600)
        )
        env.model.snapshotStore.markNotified(key: notificationKey)

        let gate = AsyncTestGate()
        env.provider.setSnapshotGate(gate)
        let refresh = Task { await env.model.refreshAll(sendNotifications: true) }
        await gate.waitForArrival()

        await env.model.deleteAccount(account.id)
        await gate.release()
        await refresh.value

        let storedAccounts = try env.model.accountStore.loadAccounts()
        let storedSnapshots = SnapshotStore(containerDirectory: env.container)
        let storedSettings = SettingsStore(containerDirectory: env.container)
        #expect(storedAccounts.isEmpty)
        #expect(storedSnapshots.snapshot(for: account.id) == nil)
        #expect(!storedSnapshots.hasManualOverride(accountID: account.id))
        #expect(!storedSnapshots.hasNotified(key: notificationKey))
        #expect(storedSettings.settings.displayLimitByAccount[account.id] == nil)
        #expect(!env.spy.sentNotifications.contains(where: { $0.accountID == account.id }))
    }

    @Test("選択中アカウントがnilならdirectとStoreの両方で新規接続先を選ぶ")
    func loginSelectionUsesNewAccountWhenNothingIsSelected() {
        for channel in [DistributionChannel.direct, .appStore] {
            #expect(LoginAccountSelectionPolicy.shouldSelectNewAccount(
                selectedAccountID: nil,
                accounts: [],
                snapshots: [:],
                distributionChannel: channel,
                placeholderDisplayName: "Default Codex Account"
            ))
        }
    }

    @Test("Storeでは唯一の未認証managed placeholderから新規接続先へ切り替える")
    func storeLoginSelectionReplacesOnlyManagedPlaceholder() {
        let placeholder = Account(displayName: "Default Codex Account", homeKind: .managed)
        #expect(LoginAccountSelectionPolicy.shouldSelectNewAccount(
            selectedAccountID: placeholder.id,
            accounts: [placeholder],
            snapshots: [:],
            distributionChannel: .appStore,
            placeholderDisplayName: placeholder.displayName
        ))

        let placeholderSnapshot = UsageSnapshot(accountID: placeholder.id)
        #expect(!LoginAccountSelectionPolicy.shouldSelectNewAccount(
            selectedAccountID: placeholder.id,
            accounts: [placeholder],
            snapshots: [placeholder.id: placeholderSnapshot],
            distributionChannel: .appStore,
            placeholderDisplayName: placeholder.displayName
        ))

        let defaultHome = Account(displayName: "Default Codex Account", homeKind: .defaultHome)
        #expect(!LoginAccountSelectionPolicy.shouldSelectNewAccount(
            selectedAccountID: defaultHome.id,
            accounts: [defaultHome],
            snapshots: [:],
            distributionChannel: .appStore,
            placeholderDisplayName: defaultHome.displayName
        ))

        let renamed = Account(displayName: "My account", homeKind: .managed)
        #expect(!LoginAccountSelectionPolicy.shouldSelectNewAccount(
            selectedAccountID: renamed.id,
            accounts: [renamed],
            snapshots: [:],
            distributionChannel: .appStore,
            placeholderDisplayName: "Default Codex Account"
        ))
    }

    @Test("Storeでは公式情報のある既存アカウントを選択し直さない")
    func storeLoginSelectionPreservesConnectedAccount() {
        let connectedByEmail = Account(
            displayName: "接続済み",
            homeKind: .managed,
            officialEmail: "person@example.test"
        )
        let connectedByPlan = Account(
            displayName: "接続済み",
            homeKind: .managed,
            officialPlanType: "plus"
        )

        for existing in [connectedByEmail, connectedByPlan] {
            #expect(!LoginAccountSelectionPolicy.shouldSelectNewAccount(
                selectedAccountID: existing.id,
                accounts: [existing],
                snapshots: [:],
                distributionChannel: .appStore,
                placeholderDisplayName: "Default Codex Account"
            ))
        }
    }

    @Test("Storeでは他アカウントがあるplaceholder選択を維持する")
    func storeLoginSelectionPreservesSelectionWhenAccountsAreMultiple() {
        let placeholder = Account(displayName: "Default Codex Account", homeKind: .managed)
        let connected = Account(
            displayName: "接続済み",
            homeKind: .managed,
            officialEmail: "person@example.test",
            officialPlanType: "plus"
        )

        #expect(!LoginAccountSelectionPolicy.shouldSelectNewAccount(
            selectedAccountID: placeholder.id,
            accounts: [placeholder, connected],
            snapshots: [:],
            distributionChannel: .appStore,
            placeholderDisplayName: placeholder.displayName
        ))
    }

    @Test("directではnil選択時以外に既存選択を変更しない")
    func directLoginSelectionPreservesExistingSelection() {
        let existing = Account(displayName: "既存", homeKind: .defaultHome)

        #expect(!LoginAccountSelectionPolicy.shouldSelectNewAccount(
            selectedAccountID: existing.id,
            accounts: [existing],
            snapshots: [:],
            distributionChannel: .direct,
            placeholderDisplayName: "Default Codex Account"
        ))
        #expect(LoginAccountSelectionPolicy.shouldSelectNewAccount(
            selectedAccountID: nil,
            accounts: [existing],
            snapshots: [:],
            distributionChannel: .direct,
            placeholderDisplayName: "Default Codex Account"
        ))
    }

    @Test("キャンセル後の遅延ログイン完了は新しいpending所有権を変更しない")
    func canceledLoginCompletionCannotCommitOrReleaseNewLogin() async throws {
        let existing = Account(
            displayName: "Existing",
            homeKind: .managed,
            officialEmail: "existing@example.test",
            officialPlanType: "plus"
        )
        let env = TestEnvironment.make(accounts: [existing], distributionChannel: .appStore)
        defer { try? FileManager.default.removeItem(at: env.container) }

        let oldClient = DelayedPendingLoginClient()
        let newClient = DelayedPendingLoginClient()
        var factoryCalls = 0
        env.model.configureLoginTesting(
            clientFactory: { _, _ in
                factoryCalls += 1
                return factoryCalls == 1 ? oldClient : newClient
            },
            openURL: { _ in }
        )

        await env.model.beginAddAccount()
        await oldClient.waitForNotificationSubscription()
        await oldClient.sendSuccessfulCompletion()
        await oldClient.waitForAccountRead()

        await env.model.cancelLogin()
        await env.model.beginAddAccount()
        await newClient.waitForNotificationSubscription()
        await env.model.beginAddAccount()
        #expect(factoryCalls == 2)

        await oldClient.releaseAccountRead()
        await oldClient.waitForLateStop()
        await oldClient.releaseLateStop()
        await Task.yield()

        await env.model.beginAddAccount()
        #expect(factoryCalls == 2, "古い完了が新しいpending clientを解放しない")
        #expect(env.model.accounts == [existing], "古い応答はアカウントを追加しない")
        #expect(env.model.settingsStore.settings.selectedAccountID == existing.id)
        #expect(env.model.loginFlow == .awaitingBrowserAuth(authURL: "https://example.invalid/"))
        #expect(try env.model.accountStore.loadAccounts() == [existing])

        await env.model.cancelLogin()
    }

    @Test("遅延した二重cancelは後続ログインの所有権を解放しない")
    func delayedDuplicateCancelCannotReleaseNewLogin() async throws {
        let existing = Account(displayName: "Existing", homeKind: .managed)
        let env = TestEnvironment.make(accounts: [existing], distributionChannel: .appStore)
        defer { try? FileManager.default.removeItem(at: env.container) }

        let oldClient = DelayedPendingLoginClient(delayFirstStop: true)
        let newClient = DelayedPendingLoginClient()
        var factoryCalls = 0
        env.model.configureLoginTesting(
            clientFactory: { _, _ in
                factoryCalls += 1
                return factoryCalls == 1 ? oldClient : newClient
            },
            openURL: { _ in }
        )

        await env.model.beginAddAccount()
        await oldClient.waitForNotificationSubscription()

        let firstCancel = Task { await env.model.cancelLogin() }
        await oldClient.waitForFirstStop()
        let secondCancel = Task { await env.model.cancelLogin() }
        await oldClient.waitForLateStop()

        await oldClient.releaseFirstStop()
        await firstCancel.value
        await env.model.beginAddAccount()
        await newClient.waitForNotificationSubscription()

        await oldClient.releaseLateStop()
        await secondCancel.value
        await env.model.beginAddAccount()

        #expect(factoryCalls == 2, "遅れて完了したcancelが新しいclientを解放しない")
        #expect(env.model.accounts == [existing])
        #expect(env.model.settingsStore.settings.selectedAccountID == existing.id)
        #expect(env.model.loginFlow == .awaitingBrowserAuth(authURL: "https://example.invalid/"))

        await env.model.cancelLogin()
    }
}
