import Foundation
import Testing
@testable import AIUsageBuddy

/// App Review 用サンプルデータ表示のテスト。
/// 通信・helper起動・保存領域への書き込み・通知が発生しないこと、Store版のみ有効なことを確認する。
@Suite
@MainActor
struct SampleModeTests {

    // MARK: - Helpers

    /// コンテナ配下の全ファイルを 相対パス → 内容 で取得する。
    private func fileContents(of container: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        let fileManager = FileManager.default
        let basePath = container.standardizedFileURL.resolvingSymlinksInPath().path
        guard let enumerator = fileManager.enumerator(
            at: container, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return result }
        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            let relative = String(path.dropFirst(basePath.count))
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            result[relative] = isDirectory ? Data("<dir>".utf8) : ((try? Data(contentsOf: url)) ?? Data())
        }
        return result
    }

    private func storeEnv() -> TestEnv {
        TestEnvironment.makeFreshInstall(distributionChannel: .appStore)
    }

    // MARK: - Data generation

    @Test("サンプルデータは(シナリオ,時刻)から決定的に生成される")
    func generationIsDeterministic() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for scenario in SampleScenario.allCases {
            #expect(SampleData.snapshots(scenario: scenario, now: now) == SampleData.snapshots(scenario: scenario, now: now))
        }
        let later = now.addingTimeInterval(600)
        let a = SampleData.snapshots(scenario: .plenty, now: now)[SampleData.firstAccountID]!
        let b = SampleData.snapshots(scenario: .plenty, now: later)[SampleData.firstAccountID]!
        #expect(a.fiveHour?.remainingPercent == b.fiveHour?.remainingPercent)
        #expect(b.fiveHour!.resetAt!.timeIntervalSince(later) == a.fiveHour!.resetAt!.timeIntervalSince(now))
    }

    @Test("サンプルは2アカウント・両枠あり・リセットは未来・取得日時なし")
    func sampleShape() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for scenario in SampleScenario.allCases {
            let snapshots = SampleData.snapshots(scenario: scenario, now: now)
            #expect(Set(snapshots.keys) == Set(SampleData.accountIDs))
            for snapshot in snapshots.values {
                #expect(snapshot.fetchedAt == nil)
                #expect(snapshot.lastErrorKind == nil)
                #expect(snapshot.fiveHour != nil && snapshot.weekly != nil)
                #expect(snapshot.fiveHour!.resetAt! > now && snapshot.weekly!.resetAt! > now)
                #expect(snapshot.fiveHour!.resetAt! < snapshot.weekly!.resetAt!)
            }
        }
        let states = SampleScenario.allCases.map {
            CharacterStateMachine.band(forPercent: SampleData.snapshots(scenario: $0, now: now)[SampleData.firstAccountID]!.fiveHour!.remainingPercent)
        }
        #expect(states == [.energetic, .tired, .sleeping])
    }

    // MARK: - Channel gating

    @Test("直接配布版ではサンプルデータを開始できない")
    func directChannelCannotStart() {
        let env = TestEnvironment.makeFreshInstall(distributionChannel: .direct)
        let before = fileContents(of: env.container)
        #expect(!env.model.canStartSampleMode)
        env.model.startSampleMode()
        #expect(!env.model.isSampleMode)
        #expect(fileContents(of: env.container) == before)
    }

    @Test("Store版かつ実アカウント未接続のときだけ開始できる")
    func storeUnconnectedCanStart() {
        let env = storeEnv()
        #expect(env.model.canStartSampleMode)
        env.model.startSampleMode()
        #expect(env.model.isSampleMode)
        #expect(!env.model.canStartSampleMode)
    }

    @Test("実アカウント接続済みのStore版では開始できない")
    func connectedStoreCannotStart() {
        let account = Account(displayName: "real", homeKind: .managed, officialEmail: "user@example.invalid")
        let env = TestEnvironment.make(accounts: [account], distributionChannel: .appStore)
        #expect(!env.model.canStartSampleMode)
        env.model.startSampleMode()
        #expect(!env.model.isSampleMode)
        #expect(env.model.accounts == [account])
    }

    // MARK: - No side effects while sampling

    @Test("サンプル中は通信・helper起動・保存領域への書き込みを行わない")
    func noNetworkNoHelperNoPersistence() async {
        let env = storeEnv()
        var clientFactoryCalls = 0
        env.model.configureLoginTesting(
            clientFactory: { _, _ in
                clientFactoryCalls += 1
                fatalError("login client must not be created in sample mode")
            },
            openURL: { _ in }
        )
        let before = fileContents(of: env.container)
        let placeholder = env.model.accounts
        env.model.startSampleMode()

        env.model.selectAccount(SampleData.secondAccountID)
        env.model.setDisplayLimit(.weekly, for: SampleData.secondAccountID)
        env.model.setSampleScenario(.low)
        await env.model.manualRefresh()
        await env.model.refreshAll(sendNotifications: true)
        await env.model.beginAddAccount()
        env.model.renameAccount(SampleData.firstAccountID, displayName: "renamed")
        await env.model.deleteAccount(SampleData.firstAccountID)
        env.model.setManualOverride(accountID: SampleData.firstAccountID, kind: .fiveHour, percent: 50)

        #expect(env.provider.fetchCallCount == 0)
        #expect(clientFactoryCalls == 0)
        #expect(env.model.accounts.map(\.id) == SampleData.accountIDs)
        #expect(env.model.accounts.first?.displayName != "renamed")
        #expect(fileContents(of: env.container) == before)
        #expect(env.model.settingsStore.settings.selectedAccountID == placeholder.first?.id)

        // 保存領域にサンプルのIDが書かれていない
        let sampleIDs = SampleData.accountIDs.map(\.uuidString)
        for data in fileContents(of: env.container).values {
            let text = String(decoding: data, as: UTF8.self)
            for id in sampleIDs { #expect(!text.contains(id)) }
        }
    }

    @Test("サンプル中は低残量でも実通知を送らない（通知設定は有効のまま）")
    func notificationsSuppressed() async {
        let env = storeEnv()
        env.model.settingsStore.settings.notificationsEnabled = true

        // 同じデータを通常経路の判定に渡せば通知対象になる（抑止が意味を持つことの確認）
        let now = Date()
        let decisions = NotificationPolicy.pendingNotifications(
            accounts: SampleData.accounts(firstName: "A", secondName: "B"),
            snapshots: SampleData.snapshots(scenario: .nearlyDepleted, now: now),
            thresholds: [20, 10],
            enabled: true,
            alreadyNotified: { _ in false },
            now: now
        )
        #expect(!decisions.isEmpty)

        env.model.startSampleMode()
        for scenario in SampleScenario.allCases {
            env.model.setSampleScenario(scenario)
            await env.model.manualRefresh()
            await env.model.refreshAll(sendNotifications: true)
        }
        #expect(env.spy.sentNotifications.isEmpty)
        #expect(env.model.settingsStore.settings.notificationsEnabled)
    }

    // MARK: - Scenarios, accounts, character

    @Test("シナリオ切替で残量と猫の状態が変わり、アカウント切替もできる")
    func scenarioAndAccountSwitching() {
        let env = storeEnv()
        env.model.startSampleMode()
        #expect(env.model.selectedAccount?.id == SampleData.firstAccountID)
        #expect(env.model.displayedPercent == 82)
        #expect(env.model.characterState == .energetic)

        env.model.setSampleScenario(.low)
        #expect(env.model.displayedPercent == 24)
        #expect(env.model.characterState == .tired)

        env.model.setSampleScenario(.nearlyDepleted)
        #expect(env.model.displayedPercent == 0)
        #expect(env.model.characterState == .sleeping)

        env.model.selectAccount(SampleData.secondAccountID)
        #expect(env.model.selectedAccount?.id == SampleData.secondAccountID)
        #expect(env.model.displayedPercent == 38)
        env.model.setDisplayLimit(.weekly, for: SampleData.secondAccountID)
        #expect(env.model.displayedPercent == 12)
    }

    // MARK: - Exit

    @Test("終了すると未接続の通常状態へ戻り、サンプルは残らない")
    func exitRestoresNormalState() {
        let env = storeEnv()
        let originalAccounts = env.model.accounts
        let originalSelected = env.model.settingsStore.settings.selectedAccountID
        let before = fileContents(of: env.container)

        env.model.startSampleMode()
        env.model.selectAccount(SampleData.secondAccountID)
        env.model.exitSampleMode()

        #expect(!env.model.isSampleMode)
        #expect(env.model.sampleScenario == nil)
        #expect(env.model.accounts == originalAccounts)
        #expect(env.model.snapshots.isEmpty)
        #expect(env.model.selectedAccount?.id == originalSelected)
        #expect(env.model.characterState == .unknown)
        #expect(env.model.displayedPercent == nil)
        #expect(fileContents(of: env.container) == before)
        // 再度開始できる
        #expect(env.model.canStartSampleMode)
    }

    @Test("サンプル状態は再起動後に引き継がれない")
    func notPersistedAcrossRestart() {
        let env = storeEnv()
        env.model.startSampleMode()
        let restarted = AppModel(
            provider: env.provider,
            settingsStore: SettingsStore(containerDirectory: env.container),
            snapshotStore: SnapshotStore(containerDirectory: env.container),
            accountStore: AccountStore(containerDirectory: env.container),
            notificationScheduler: SpyNotificationScheduler(),
            localization: LocalizationManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!),
            loginItemManager: SpyLoginItemManager(),
            windowPresenter: AppWindowPresenter(host: SpyWindowHost()),
            shortcutManager: GlobalShortcutManager(registrar: SpyHotKeyRegistrar()),
            distributionChannel: .appStore
        )
        #expect(!restarted.isSampleMode)
        #expect(!restarted.accounts.contains { SampleData.accountIDs.contains($0.id) })
    }
}
