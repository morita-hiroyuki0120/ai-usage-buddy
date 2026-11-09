import Foundation
import UserNotifications
@testable import AIUsageBuddy

actor AsyncTestGate {
    private var arrived = false
    private var released = false
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        arrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        guard !released else { return }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    func waitForArrival() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

/// ライブデータに依存しないテスト用 UsageProvider。
final class MockUsageProvider: UsageProvider, AccountLogoutProviding, @unchecked Sendable {

    private let lock = NSLock()
    private var _accounts: [Account] = []
    private var _snapshots: [UUID: UsageSnapshot] = [:]
    private var _accountInfos: [UUID: Account] = [:]
    private var _fetchError: Error?
    private var _accountsError: Error?
    private var _accountsGate: AsyncTestGate?
    private var _snapshotGate: AsyncTestGate?
    private var _logoutHandler: (@Sendable (Account) async throws -> Void)?
    private var _logoutCallCount = 0

    var logoutCallCount: Int { synchronized { _logoutCallCount } }

    func setLogoutHandler(_ handler: @escaping @Sendable (Account) async throws -> Void) {
        synchronized { _logoutHandler = handler }
    }

    func logoutAndStop(for account: Account) async throws {
        let handler = synchronized {
            _logoutCallCount += 1
            return _logoutHandler
        }
        guard let handler else { throw CodexClientError.storeHelperMissing }
        try await handler(account)
    }

    private var _fetchCallCount = 0

    var fetchCallCount: Int {
        synchronized { _fetchCallCount }
    }

    /// 非同期コンテキストからNSLockを直接触らないための同期ヘルパ。
    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// throws 版。
    private func synchronizedThrows<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func setAccounts(_ accounts: [Account]) {
        synchronized { _accounts = accounts }
    }

    func setSnapshot(_ snapshot: UsageSnapshot) {
        synchronized { _snapshots[snapshot.accountID] = snapshot }
    }

    func setAccountInfo(_ account: Account) {
        synchronized { _accountInfos[account.id] = account }
    }

    func setFetchError(_ error: Error?) {
        synchronized { _fetchError = error }
    }

    func setAccountsGate(_ gate: AsyncTestGate?) {
        synchronized { _accountsGate = gate }
    }

    func setSnapshotGate(_ gate: AsyncTestGate?) {
        synchronized { _snapshotGate = gate }
    }

    func accounts() async throws -> [Account] {
        let (error, accounts, gate) = synchronized { (_accountsError, _accounts, _accountsGate) }
        if let gate { await gate.pause() }
        if let error { throw error }
        return accounts
    }

    func fetchSnapshot(for account: Account) async throws -> UsageSnapshot {
        let (error, snapshot, gate): (Error?, UsageSnapshot?, AsyncTestGate?) = synchronized {
            _fetchCallCount += 1
            return (_fetchError, _snapshots[account.id], _snapshotGate)
        }

        if let gate { await gate.pause() }
        if let error { throw error }
        guard let snapshot else {
            throw CodexClientError.invalidResponse("no snapshot configured for \(account.id)")
        }
        return snapshot
    }

    func fetchAccountInfo(for account: Account) async throws -> Account {
        synchronized { _accountInfos[account.id] ?? account }
    }
}

/// テスト用の通知スパイ。実際には通知を送らない。
@MainActor
final class SpyNotificationScheduler: NotificationScheduling, ObservableObject {
    @Published var authorizationStatus: UNAuthorizationStatus = .authorized

    private(set) var sentNotifications: [NotificationPolicy.Decision] = []
    private(set) var authorizationRequested = false

    nonisolated func refreshAuthorizationStatus() async {}

    func requestAuthorization() async -> Bool {
        authorizationRequested = true
        return true
    }

    func sendLowUsageNotification(_ decision: NotificationPolicy.Decision, language: AppLanguage) async {
        sentNotifications.append(decision)
    }

    func openSystemNotificationSettings() {}
}

/// テスト用のログイン項目スパイ。実際にはSMAppServiceを触らない。
final class SpyLoginItemManager: LoginItemManaging, @unchecked Sendable {

    private let lock = NSLock()
    private var _enabled = false

    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    /// true なら登録・解除とも失敗を返す。
    var shouldFail = false

    func isEnabled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _enabled
    }

    func setEnabled(_ enabled: Bool) -> Result<Void, LoginItemError> {
        lock.lock(); defer { lock.unlock() }
        if shouldFail {
            return .failure(LoginItemError(message: "test registration failure"))
        }
        if enabled {
            registerCount += 1
        } else {
            unregisterCount += 1
        }
        _enabled = enabled
        return .success(())
    }
}

/// テスト用のホットキー登録スパイ。Carbon を触らない。
/// 実装と同じく「register は同一IDの既存登録を置き換える」セマンティクス。
final class SpyHotKeyRegistrar: HotKeyRegistering, @unchecked Sendable {

    struct Registration: Equatable, Sendable {
        let id: UInt32
        let keyCode: Int
        let modifiers: Int
    }

    private let lock = NSLock()
    private var _active: [UInt32: Registration] = [:]
    private var _registerCalls: [Registration] = []
    private var _unregisteredIDs: [UInt32] = []

    /// true なら登録に失敗する。
    var shouldFail = false

    @discardableResult
    func register(id: UInt32, keyCode: Int, modifiers: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if shouldFail { return false }
        let registration = Registration(id: id, keyCode: keyCode, modifiers: modifiers)
        _active[id] = registration
        _registerCalls.append(registration)
        return true
    }

    func unregister(id: UInt32) {
        lock.lock(); defer { lock.unlock() }
        _active.removeValue(forKey: id)
        _unregisteredIDs.append(id)
    }

    /// 成功した register 呼び出しの履歴（置換も含む）。
    var registerCalls: [Registration] {
        lock.lock(); defer { lock.unlock() }
        return _registerCalls
    }

    var unregisteredIDs: [UInt32] {
        lock.lock(); defer { lock.unlock() }
        return _unregisteredIDs
    }

    /// 現在有効な登録。
    var activeRegistrations: [Registration] {
        lock.lock(); defer { lock.unlock() }
        return Array(_active.values)
    }

    /// 現在有効なID。
    var activeIDs: [UInt32] {
        lock.lock(); defer { lock.unlock() }
        return Array(_active.keys)
    }
}

/// テスト用の更新取得スパイ。
final class SpyUpdateProvider: UpdateProviding, @unchecked Sendable {

    private let lock = NSLock()
    private var _release: UpdateRelease = UpdateRelease(version: "1.0.0")
    private var _error: Error?
    private var _fetchCount = 0

    func setRelease(_ release: UpdateRelease) {
        lock.lock(); defer { lock.unlock() }
        _release = release
    }

    func setError(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        _error = error
    }

    var fetchCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _fetchCount
    }

    func fetchLatestRelease() async throws -> UpdateRelease {
        // ロックは同期ヘルパ内で行う（asyncコンテキストでの直接ロックを避ける）
        let state = currentState()
        recordFetch()
        if let error = state.error { throw error }
        return state.release
    }

    private func currentState() -> (release: UpdateRelease, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        return (_release, _error)
    }

    private func recordFetch() {
        lock.lock(); defer { lock.unlock() }
        _fetchCount += 1
    }
}

/// テスト用の一時コンテナと依存のセット。
@MainActor
struct TestEnv {
    let model: AppModel
    let provider: MockUsageProvider
    let spy: SpyNotificationScheduler
    let container: URL
    let loginItemSpy: SpyLoginItemManager
    let windowHost: SpyWindowHost
    let shortcutRegistrar: SpyHotKeyRegistrar
}

@MainActor
enum TestEnvironment {

    /// 既存インストール相当（accounts.json が先に存在する）の環境を作る。
    /// 既存テストと同じ挙動: 自動アカウント作成なし・既存ユーザー扱い。
    static func make(
        accounts: [Account] = [],
        snapshots: [UsageSnapshot] = [],
        distributionChannel: DistributionChannel = .direct,
        codexBundleURL: URL = Bundle.main.bundleURL
    ) -> TestEnv {
        makeInternal(
            accounts: accounts,
            snapshots: snapshots,
            preCreateMarkerFile: !accounts.isEmpty,
            distributionChannel: distributionChannel,
            codexBundleURL: codexBundleURL
        )
    }

    /// 新規インストール相当（永続化ファイルが一切無い状態から開始）の環境を作る。
    static func makeFreshInstall(
        accounts: [Account] = [],
        snapshots: [UsageSnapshot] = [],
        distributionChannel: DistributionChannel = .direct
    ) -> TestEnv {
        makeInternal(
            accounts: accounts,
            snapshots: snapshots,
            preCreateMarkerFile: false,
            distributionChannel: distributionChannel,
            codexBundleURL: Bundle.main.bundleURL
        )
    }

    private static func makeInternal(
        accounts: [Account],
        snapshots: [UsageSnapshot],
        preCreateMarkerFile: Bool,
        distributionChannel: DistributionChannel,
        codexBundleURL: URL
    ) -> TestEnv {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AIUsageBuddyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let provider = MockUsageProvider()
        provider.setAccounts(accounts)
        for snapshot in snapshots {
            provider.setSnapshot(snapshot)
        }

        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let localization = LocalizationManager(defaults: defaults)

        // 既存ユーザー扱いにする場合のみAppModelの初期化前にアカウントを保存する
        // （初回セットアップの判定はaccounts.json等の存在で行うため）
        let accountStore = AccountStore(containerDirectory: container)
        if preCreateMarkerFile {
            try? accountStore.saveAccounts(accounts)
        }

        let spy = SpyNotificationScheduler()
        let loginItemSpy = SpyLoginItemManager()
        let windowHost = SpyWindowHost()
        let shortcutRegistrar = SpyHotKeyRegistrar()

        let model = AppModel(
            provider: provider,
            settingsStore: SettingsStore(containerDirectory: container),
            snapshotStore: SnapshotStore(containerDirectory: container),
            accountStore: accountStore,
            notificationScheduler: spy,
            localization: localization,
            loginItemManager: loginItemSpy,
            updateService: UpdateService(
                provider: SpyUpdateProvider(),
                defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
                // UpdateServiceのバージョン既定はBundle（Info.plist）由来になり、
                // テストランナーでは "0.0.0" になるため明示する
                currentVersion: "1.0.0",
                distributionChannel: distributionChannel
            ),
            windowPresenter: AppWindowPresenter(host: windowHost),
            shortcutManager: GlobalShortcutManager(registrar: shortcutRegistrar),
            distributionChannel: distributionChannel,
            codexBundleURL: codexBundleURL
        )
        if !accounts.isEmpty {
            model.settingsStore.settings.selectedAccountID = accounts.first?.id
        }
        return TestEnv(
            model: model,
            provider: provider,
            spy: spy,
            container: container,
            loginItemSpy: loginItemSpy,
            windowHost: windowHost,
            shortcutRegistrar: shortcutRegistrar
        )
    }
}
