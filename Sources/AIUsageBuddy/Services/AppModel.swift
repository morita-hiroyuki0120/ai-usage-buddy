import Foundation
import Combine
import AppKit
import SwiftUI

protocol PendingLoginClient: Actor {
    func start() async throws
    func startLogin() async throws -> LoginStartResult
    func notifications() -> AsyncStream<ServerNotification>
    func readAccount() async throws -> GetAccountResponse
    func stop() async
}

extension CodexAppServerClient: PendingLoginClient {}

typealias PendingLoginClientFactory = @MainActor (URL, UUID) -> any PendingLoginClient
typealias LoginURLHandler = @MainActor (URL) -> Void

/// アカウント追加（公式OAuthログイン）フローの状態。
public enum LoginFlowState: Equatable, Sendable {
    case idle
    /// authUrl を表示中（ユーザーがブラウザで認証を行う段階）。
    case awaitingBrowserAuth(authURL: String)
    /// 認証完了を app-server からの通知で待機中。
    case completing
    case success(accountName: String)
    case failed(errorMessage: String)
}

enum LoginAccountSelectionPolicy {
    static func shouldSelectNewAccount(
        selectedAccountID: UUID?,
        accounts: [Account],
        snapshots: [UUID: UsageSnapshot],
        distributionChannel: DistributionChannel,
        placeholderDisplayName: String
    ) -> Bool {
        guard let selectedAccountID else { return true }
        guard distributionChannel.isAppStore,
              accounts.count == 1,
              let existing = accounts.first,
              existing.id == selectedAccountID,
              existing.displayName == placeholderDisplayName,
              existing.homeKind == .managed,
              existing.officialEmail == nil,
              existing.officialPlanType == nil,
              snapshots[existing.id] == nil
        else { return false }
        return true
    }
}

/// アプリ全体の状態を保持し、定期取得・通知・アカウント管理を統括するモデル。
@MainActor
public final class AppModel: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var snapshots: [UUID: UsageSnapshot] = [:]
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefreshCompletedAt: Date?
    @Published public private(set) var loginFlow: LoginFlowState = .idle
    /// メニューバーに表示するキャラクター状態。
    @Published public private(set) var characterState: CharacterState = .unknown
    /// 選択中アカウント＋表示リミットにおける残量（%）。
    @Published public private(set) var displayedPercent: Int?
    /// 選択中アカウントの表示リミット。
    @Published public var selectedDisplayLimit: QuotaLimitKind = .fiveHour

    /// 初回セットアップをまだ表示していない（新規インストールで未完了）か。
    @Published public private(set) var onboardingPending = false
    /// 初回セットアップ実行中（ウィンドウ表示中）か。
    @Published public private(set) var onboardingActive = false
    /// 初回セットアップの現在ステップ。
    @Published public private(set) var onboardingStep: OnboardingStep = .welcome
    /// ログイン項目登録の直近エラー（UI表示用）。
    @Published public private(set) var launchAtLoginError: String?
    /// アカウント削除に失敗した場合の安全なUIメッセージ。
    @Published public private(set) var accountDeletionErrorMessage: String?
    /// サンプルデータ表示（App Review 用）の状態。メモリ上のみで保持し、永続化しない。
    @Published public private(set) var sampleSession: SampleSession?

    public let settingsStore: SettingsStore
    public let snapshotStore: SnapshotStore
    public let accountStore: AccountStore
    public let localization: LocalizationManager
    public let updateService: UpdateService
    public let distributionChannel: DistributionChannel
    public let shortcutManager: GlobalShortcutManager
    public let windowPresenter: AppWindowPresenter
    private let notificationCenter: any NotificationScheduling
    private let loginItemManager: any LoginItemManaging

    private let provider: UsageProvider
    private let codexBundleURL: URL
    private let stateMachine = CharacterStateMachine()
    /// accountID|limit ごとの直前キャラクター状態（ヒステリシス用）。
    private var lastCharacterStates: [String: CharacterState] = [:]
    private var accountListRevision: UInt64 = 0
    private var accountRefreshRevision: [UUID: UInt64] = [:]
    private var pendingAccountDeletions: Set<UUID> = []
    private var autoRefreshTask: Task<Void, Never>?
    private let logger = AppLogger(category: "AppModel")
#if DEBUG
    private var loginClientFactory: PendingLoginClientFactory?
    private var loginURLHandler: LoginURLHandler?
#endif

    // MARK: - Init

    public init(
        provider: UsageProvider? = nil,
        settingsStore: SettingsStore? = nil,
        snapshotStore: SnapshotStore? = nil,
        accountStore: AccountStore? = nil,
        notificationScheduler: (any NotificationScheduling)? = nil,
        localization: LocalizationManager? = nil,
        loginItemManager: (any LoginItemManaging)? = nil,
        updateService: UpdateService? = nil,
        windowPresenter: AppWindowPresenter? = nil,
        shortcutManager: GlobalShortcutManager? = nil,
        distributionChannel: DistributionChannel = .current,
        codexBundleURL: URL = Bundle.main.bundleURL
    ) {
        self.settingsStore = settingsStore ?? SettingsStore.shared
        self.snapshotStore = snapshotStore ?? SnapshotStore.shared
        self.accountStore = accountStore ?? AccountStore.current
        self.distributionChannel = distributionChannel
        self.codexBundleURL = codexBundleURL
        self.provider = provider ?? CodexUsageProvider(
            distributionChannel: distributionChannel,
            accountStore: self.accountStore
        )
        self.notificationCenter = notificationScheduler ?? NotificationScheduler.shared
        self.localization = localization ?? LocalizationManager.shared
        self.loginItemManager = loginItemManager ?? SMAppServiceLoginItemManager()
        self.updateService = updateService ?? UpdateService(distributionChannel: distributionChannel)
        self.windowPresenter = windowPresenter ?? AppWindowPresenter()
        self.shortcutManager = shortcutManager ?? GlobalShortcutManager()

        // 既定アカウントを自動作成する前に、新規インストールか既存かを判定する
        // （accounts.json は自動作成で即座に書かれるため、判定が先）。
        let installStatus = InstallDetector.detect(container: self.settingsStore.containerDirectory)

        loadPersistedState()

        if distributionChannel.isAppStore {
            isolatePersistedAccountsForStore()
        }

        // 初回起動時にアカウントが無ければ既定のCodexホームを参照するアカウントを自動作成する
        if accounts.isEmpty {
            let homeKind: Account.HomeKind = distributionChannel.isAppStore ? .managed : .defaultHome
            let account = Account(displayName: L("account.default.name"), homeKind: homeKind)
            let homeReady = !distributionChannel.isAppStore
                || (try? self.accountStore.prepareManagedHome(for: account.id)) != nil
            if homeReady, (try? self.accountStore.upsert(account)) != nil {
                self.accounts = [account]
                self.settingsStore.settings.selectedAccountID = account.id
            }
        }
        if let selected = self.settingsStore.settings.selectedAccountID {
            selectedDisplayLimit = self.settingsStore.displayLimit(for: selected)
        }

        switch installStatus {
        case .existingInstall:
            // 既存ユーザーには初回セットアップを表示しない（未完了フラグは完了扱いへ移行）
            if !self.settingsStore.settings.onboardingCompleted {
                self.settingsStore.markOnboardingCompleted(version: OnboardingFlow.currentVersion)
            }
            self.onboardingPending = false
        case .freshInstall:
            self.onboardingPending = !self.settingsStore.settings.onboardingCompleted
        }
    }

    private func loadPersistedState() {
        accounts = (try? accountStore.loadAccounts()) ?? []
        snapshots = snapshotStore.allSnapshots()
    }

    private func isolatePersistedAccountsForStore() {
        var migrated = accounts
        for index in migrated.indices where migrated[index].homeKind == .defaultHome {
            let accountID = migrated[index].id
            migrated[index].homeKind = .managed
            migrated[index].officialEmail = nil
            migrated[index].officialPlanType = nil
            _ = try? accountStore.prepareManagedHome(for: accountID)
            snapshotStore.clearAccountData(accountID: accountID)
        }
        guard migrated != accounts else { return }
        do {
            try accountStore.saveAccounts(migrated)
            accounts = migrated
            snapshots = snapshotStore.allSnapshots()
        } catch {
            logger.error("failed to isolate Store accounts")
        }
    }

    // MARK: - Lifecycle

    /// 起動時の即時取得と自動更新ループを開始する。
    public func start() {
        Task { await performStartupActions() }
        startAutoRefreshLoop()
        applyShortcutSettings()
    }

    /// 起動直後の一連の処理（テストから直接待機できるように分離）。
    public func performStartupActions() async {
        await refreshAll(sendNotifications: false)
        await requestNotificationAuthorizationIfNeeded()
        if !distributionChannel.isAppStore {
            await updateService.automaticCheckIfNeeded(
                enabled: settingsStore.settings.automaticUpdateChecksEnabled
            )
        }
    }

    public func stop() async {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        shortcutManager.unregisterAll()
        if pendingLoginClient != nil {
            await cancelLogin()
        }
        if let codexProvider = provider as? CodexUsageProvider {
            await codexProvider.stopAll()
        }
    }

    private func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let interval = self.settingsStore.settings.autoRefreshInterval
                try? await Task.sleep(nanoseconds: UInt64(max(10, interval) * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.refreshAll(sendNotifications: true)
            }
        }
    }

    // MARK: - Refresh

    /// 全アカウントの利用枠を公式経路から取得する。
    /// - Parameter sendNotifications: 自動更新時のみ true（起動直後の初回は通知しない）。
    public func refreshAll(sendNotifications: Bool) async {
        // サンプルデータ表示中は通信・helper起動・通知を一切行わない。
        if isSampleMode {
            refreshSampleSnapshots()
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshCompletedAt = Date()
        }

        // 削除と競合して返った古い一覧は採用しない。
        let listRevision = accountListRevision
        if let loaded = try? await provider.accounts(),
           listRevision == accountListRevision,
           pendingAccountDeletions.isEmpty {
            let storedAccounts = (try? accountStore.loadAccounts()) ?? []
            let storedIDs = Set(storedAccounts.map(\.id))
            accounts = loaded.filter { storedIDs.contains($0.id) }
        }

        for account in accounts {
            let refreshRevision = accountRefreshRevision[account.id, default: 0]
            guard canCommitRefresh(for: account.id, revision: refreshRevision) else { continue }
            do {
                // 公式識別情報も更新（表示名の元など）
                if let updated = try? await provider.fetchAccountInfo(for: account) {
                    guard canCommitRefresh(for: account.id, revision: refreshRevision) else { continue }
                    if let index = accounts.firstIndex(where: { $0.id == updated.id }) {
                        // ユーザー設定の表示名を保持しつつ公式情報のみ反映
                        var merged = accounts[index]
                        merged.officialEmail = updated.officialEmail
                        merged.officialPlanType = updated.officialPlanType
                        accounts[index] = merged
                        try? accountStore.upsert(merged)
                    }
                }
                guard canCommitRefresh(for: account.id, revision: refreshRevision) else { continue }
                let snapshot = try await provider.fetchSnapshot(for: account)
                guard canCommitRefresh(for: account.id, revision: refreshRevision) else { continue }
                snapshotStore.storeOfficialSnapshot(snapshot)
                snapshots[account.id] = snapshot
            } catch {
                guard canCommitRefresh(for: account.id, revision: refreshRevision) else { continue }
                // 取得失敗時は前回値を表示し stale 警告を出す。
                // エラーは種別ごとに分類して保存する（詳細は認証情報・秘密URLを検閲済み）。
                let kind = UsageErrorKind.classify(error)
                snapshotStore.markStale(
                    accountID: account.id,
                    kind: kind,
                    detail: error.localizedDescription
                )
                snapshots[account.id] = snapshotStore.snapshot(for: account.id)
                logger.error("fetch failed for account \(account.id): kind=\(kind.rawValue)")
            }
        }

        recomputeDisplayedState()

        if sendNotifications {
            await deliverPendingNotifications()
        }
    }

    private func canCommitRefresh(for accountID: UUID, revision: UInt64) -> Bool {
        guard !pendingAccountDeletions.contains(accountID),
              accountRefreshRevision[accountID, default: 0] == revision,
              accounts.contains(where: { $0.id == accountID }) else {
            return false
        }
        let storedAccounts = (try? accountStore.loadAccounts()) ?? []
        return storedAccounts.contains(where: { $0.id == accountID })
    }

    /// 手動更新ボタンからの取得。
    public func manualRefresh() async {
        await refreshAll(sendNotifications: true)
    }

    // MARK: - Character state

    /// 選択中アカウント＋表示リミットに基づいてキャラクター状態と残量を再計算する。
    public func recomputeDisplayedState() {
        guard let selectedID = effectiveSelectedAccountID,
              let snapshot = snapshots[selectedID] else {
            characterState = .unknown
            displayedPercent = nil
            return
        }
        let limit = displayLimit(for: selectedID)
        selectedDisplayLimit = limit
        let key = "\(selectedID.uuidString)|\(limit.rawValue)"

        if let window = snapshot.window(for: limit) {
            displayedPercent = window.remainingPercent
            let previous = lastCharacterStates[key]
            let next = stateMachine.next(current: previous ?? .unknown, percent: window.remainingPercent)
            lastCharacterStates[key] = next
            characterState = next
        } else {
            displayedPercent = nil
            characterState = .unknown
        }
    }

    // MARK: - Selection

    public var selectedAccount: Account? {
        guard let id = effectiveSelectedAccountID else { return nil }
        return accounts.first { $0.id == id }
    }

    /// 選択中アカウントID。サンプルデータ表示中は設定ファイルに触れずメモリ上の選択を使う。
    private var effectiveSelectedAccountID: UUID? {
        if let sampleSession { return sampleSession.selectedAccountID }
        return settingsStore.settings.selectedAccountID
    }

    /// アカウントごとの表示リミット。サンプルデータ表示中は設定ファイルに触れない。
    public func displayLimit(for accountID: UUID) -> QuotaLimitKind {
        if let sampleSession { return sampleSession.displayLimits[accountID] ?? .fiveHour }
        return settingsStore.displayLimit(for: accountID)
    }

    public func selectAccount(_ id: UUID) {
        if sampleSession != nil {
            guard accounts.contains(where: { $0.id == id }) else { return }
            sampleSession?.selectedAccountID = id
        } else {
            settingsStore.settings.selectedAccountID = id
        }
        selectedDisplayLimit = displayLimit(for: id)
        // 表示コンテキストが変わるためキャラクター状態はバンドから再導出する
        recomputeDisplayedState()
    }

    public func setDisplayLimit(_ limit: QuotaLimitKind, for accountID: UUID) {
        if sampleSession != nil {
            sampleSession?.displayLimits[accountID] = limit
        } else {
            settingsStore.setDisplayLimit(limit, for: accountID)
        }
        if effectiveSelectedAccountID == accountID {
            selectedDisplayLimit = limit
        }
        recomputeDisplayedState()
    }

    // MARK: - Onboarding

    /// 初回セットアップを開始する（設定・右クリックメニューからの再実行でも使う）。
    public func startOnboarding() {
        onboardingStep = .welcome
        onboardingActive = true
        windowPresenter.showOnboarding(content: self.onboardingContent())
    }

    /// 初回セットアップをスキップする（完了扱いにして再表示しない）。
    public func skipOnboarding() {
        finishOnboarding()
    }

    /// 初回セットアップを完了する。
    public func completeOnboarding() {
        finishOnboarding()
    }

    private func finishOnboarding() {
        settingsStore.markOnboardingCompleted(version: OnboardingFlow.currentVersion)
        onboardingPending = false
        onboardingActive = false
        windowPresenter.closeOnboarding()
    }

    /// ステップを進める（最終ステップの次で完了）。
    public func advanceOnboarding() {
        guard let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        onboardingStep = next
    }

    /// 指定ステップへ移動する（戻る操作用）。
    public func goToOnboardingStep(_ step: OnboardingStep) {
        onboardingStep = step
    }

    private func onboardingContent() -> AnyView {
        AnyView(OnboardingView(model: self))
    }

    // MARK: - Launch at login

    /// ログイン時自動起動の登録／解除。必ずユーザーの明示操作から呼ぶ。
    public func setLaunchAtLogin(_ enabled: Bool) {
        switch loginItemManager.setEnabled(enabled) {
        case .success:
            settingsStore.settings.launchAtLogin = enabled
            launchAtLoginError = nil
        case .failure(let error):
            launchAtLoginError = error.message
            // 実際の状態へ同期する
            settingsStore.settings.launchAtLogin = loginItemManager.isEnabled()
        }
    }

    // MARK: - Global shortcuts & quick usage window

    /// ショートカット設定を保存して反映する（検証・登録結果は shortcutManager が保持）。
    public func updateShortcuts(show: HotKeySpec, refresh: HotKeySpec) {
        settingsStore.updateShortcuts(show: show, refresh: refresh)
        applyShortcutSettings()
    }

    /// 保存済みショートカットをホットキー登録へ反映する。
    public func applyShortcutSettings() {
        shortcutManager.onShowUsage = { [weak self] in
            self?.toggleQuickUsageWindow()
        }
        shortcutManager.onRefresh = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.manualRefresh()
            }
        }
        shortcutManager.apply(
            show: settingsStore.settings.showUsageShortcut,
            refresh: settingsStore.settings.refreshShortcut
        )
    }

    /// クイック利用状況ウインドウの表示／非表示切替。
    /// 中身はポップオーバーと同じ PopoverView（表示ロジックの共有）。
    public func toggleQuickUsageWindow() {
        windowPresenter.toggleQuickUsage(content: self.quickUsageContent())
    }

    private func quickUsageContent() -> AnyView {
        AnyView(PopoverView(model: self))
    }

    // MARK: - Menu bar context menu

    /// 設定ウィンドウを開く（ポップオーバー・右クリックメニュー共通の導線）。
    public func openSettingsWindow() {
        windowPresenter.showSettings(content: AnyView(SettingsView(model: self)))
    }

    /// 右クリックメニューの選択を処理する。
    public func handleMenuBarContextAction(_ action: MenuBarContextAction) {
        switch action {
        case .refreshNow:
            Task { await manualRefresh() }
        case .selectAccount(let id):
            selectAccount(id)
        case .rerunOnboarding:
            startOnboarding()
        case .openSettings:
            openSettingsWindow()
        case .checkForUpdates:
            guard !distributionChannel.isAppStore else { return }
            openSettingsWindow()
            Task { await updateService.checkNow() }
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// 右クリックメニューの構成（MenuBarContextMenuBuilder へ渡す現在状態）。
    public var menuBarContextState: (accounts: [Account], selectedAccountID: UUID?, isRefreshing: Bool) {
        (
            accounts,
            effectiveSelectedAccountID,
            isRefreshing
        )
    }

    // MARK: - Sample data mode (App Review)

    /// サンプルデータ表示の一時状態。メモリ上のみ。アプリ再起動で必ず通常状態に戻る。
    public struct SampleSession: Equatable {
        public var scenario: SampleScenario
        var selectedAccountID: UUID?
        var displayLimits: [UUID: QuotaLimitKind] = [:]
        /// 開始前の（実）状態。終了時にそのまま戻す。永続化データには触れない。
        let stashedAccounts: [Account]
        let stashedSnapshots: [UUID: UsageSnapshot]
    }

    public var isSampleMode: Bool { sampleSession != nil }
    public var sampleScenario: SampleScenario? { sampleSession?.scenario }

    /// サンプルデータ表示を開始できるか。
    /// Store 版のみ・実アカウント未接続のときだけ true（接続済みの実データと混在させない）。
    public var canStartSampleMode: Bool {
        guard distributionChannel.isAppStore, sampleSession == nil, pendingLoginClient == nil else {
            return false
        }
        let hasConnectedAccount = accounts.count > 1
            || accounts.contains { $0.officialEmail != nil || $0.officialPlanType != nil }
            || snapshots.values.contains { !$0.isEmpty }
        return !hasConnectedAccount
    }

    /// サンプルデータ表示を開始する。通信・認証・Keychain・保存領域には一切触れない。
    public func startSampleMode() {
        guard canStartSampleMode else { return }
        invalidateInFlightRefreshes()
        let sampleAccounts = SampleData.accounts(
            firstName: L("sample.account.first"),
            secondName: L("sample.account.second")
        )
        sampleSession = SampleSession(
            scenario: .plenty,
            selectedAccountID: sampleAccounts.first?.id,
            stashedAccounts: accounts,
            stashedSnapshots: snapshots
        )
        accounts = sampleAccounts
        snapshots = SampleData.snapshots(scenario: .plenty, now: Date())
        removeSampleCharacterStates()
        selectedDisplayLimit = displayLimit(for: SampleData.firstAccountID)
        recomputeDisplayedState()
    }

    /// サンプルデータ表示を終了し、開始前の状態へ戻す。
    public func exitSampleMode() {
        guard let session = sampleSession else { return }
        invalidateInFlightRefreshes()
        sampleSession = nil
        accounts = session.stashedAccounts
        snapshots = session.stashedSnapshots
        removeSampleCharacterStates()
        if let selected = settingsStore.settings.selectedAccountID {
            selectedDisplayLimit = settingsStore.displayLimit(for: selected)
        }
        recomputeDisplayedState()
    }

    /// 残量シナリオを切り替える。
    public func setSampleScenario(_ scenario: SampleScenario) {
        guard sampleSession != nil else { return }
        sampleSession?.scenario = scenario
        refreshSampleSnapshots()
    }

    private func refreshSampleSnapshots() {
        guard let session = sampleSession else { return }
        snapshots = SampleData.snapshots(scenario: session.scenario, now: Date())
        recomputeDisplayedState()
    }

    /// 開始・終了をまたいで、進行中の実取得結果が表示状態へ反映されないようにする。
    private func invalidateInFlightRefreshes() {
        accountListRevision &+= 1
        for account in accounts {
            accountRefreshRevision[account.id, default: 0] &+= 1
        }
    }

    private func removeSampleCharacterStates() {
        for id in SampleData.accountIDs {
            for limit in QuotaLimitKind.allCases {
                lastCharacterStates.removeValue(forKey: "\(id.uuidString)|\(limit.rawValue)")
            }
        }
    }

    // MARK: - Manual override

    public func setManualOverride(accountID: UUID, kind: QuotaLimitKind, percent: Int) {
        guard !isSampleMode else { return }
        snapshotStore.setManualOverride(accountID: accountID, kind: kind, percent: percent)
        snapshots[accountID] = snapshotStore.snapshot(for: accountID)
        recomputeDisplayedState()
    }

    public func clearManualOverride(accountID: UUID, kind: QuotaLimitKind) {
        guard !isSampleMode else { return }
        snapshotStore.clearManualOverride(accountID: accountID, kind: kind)
        snapshots[accountID] = snapshotStore.snapshot(for: accountID)
        recomputeDisplayedState()
    }

    // MARK: - Notifications

    private func requestNotificationAuthorizationIfNeeded() async {
        guard settingsStore.settings.notificationsEnabled else { return }
        // 初回セットアップが未完了の間はシステムダイアログを出さない。
        // 許可はセットアップの通知ステップ（または設定トグル）で明示的に要求する。
        guard !onboardingPending else { return }
        _ = await notificationCenter.requestAuthorization()
    }

    /// 初回セットアップの通知ステップで、ユーザーの明示操作により許可を要求する。
    public func requestNotificationAuthorizationFromOnboarding() async {
        _ = await notificationCenter.requestAuthorization()
    }

    private func deliverPendingNotifications() async {
        // サンプルデータは実際の利用状況ではないため、実通知は送らない。
        guard !isSampleMode else { return }
        let settings = settingsStore.settings
        let decisions = NotificationPolicy.pendingNotifications(
            accounts: accounts,
            snapshots: snapshots,
            thresholds: settings.notificationThresholds,
            enabled: settings.notificationsEnabled,
            alreadyNotified: { snapshotStore.hasNotified(key: $0) }
        )
        let language = localization.currentLanguage
        for decision in decisions {
            let revision = accountRefreshRevision[decision.accountID, default: 0]
            guard canCommitRefresh(for: decision.accountID, revision: revision) else { continue }
            await notificationCenter.sendLowUsageNotification(decision, language: language)
            guard canCommitRefresh(for: decision.accountID, revision: revision) else { continue }
            snapshotStore.markNotified(key: decision.key)
        }
    }

    // MARK: - Account management

    /// 新規アカウント追加: 公式OAuthログインフローを開始する。
    public func beginAddAccount() async {
        guard !isSampleMode, pendingLoginClient == nil else { return }
        let accountID = UUID()
        var client: (any PendingLoginClient)?
        var createdClient = false
        do {
            let home = try accountStore.prepareManagedHome(for: accountID)
#if DEBUG
            let newClient: any PendingLoginClient
            if let loginClientFactory {
                newClient = loginClientFactory(home, accountID)
            } else {
                newClient = CodexAppServerClient(
                    codexHome: home,
                    distributionChannel: distributionChannel,
                    bundleURL: codexBundleURL,
                    accountID: accountID,
                    containerDirectory: accountStore.containerDirectory
                )
            }
#else
            let newClient: any PendingLoginClient = CodexAppServerClient(
                codexHome: home,
                distributionChannel: distributionChannel,
                bundleURL: codexBundleURL,
                accountID: accountID,
                containerDirectory: accountStore.containerDirectory
            )
#endif
            client = newClient
            createdClient = true
            // 登録は最初のawaitより前に行い、終了要求が起動中の子も所有できるようにする。
            pendingLoginClient = newClient
            pendingLoginAccountID = accountID
            try await newClient.start()
            try Task.checkCancellation()
            guard pendingLoginAccountID == accountID else {
                await newClient.stop()
                return
            }

            let login = try await newClient.startLogin()
            try Task.checkCancellation()
            guard pendingLoginAccountID == accountID else {
                await newClient.stop()
                return
            }
            guard let authURL = login.authUrl else {
                await newClient.stop()
                guard pendingLoginAccountID == accountID else { return }
                releasePendingLoginClient(for: accountID)
                try? accountStore.delete(accountID: accountID)
                loginFlow = .failed(errorMessage: "app-server did not return an authUrl")
                return
            }
            loginFlow = .awaitingBrowserAuth(authURL: authURL)
            if let url = URL(string: authURL) {
#if DEBUG
                if let loginURLHandler {
                    loginURLHandler(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
#else
                NSWorkspace.shared.open(url)
#endif
            }
            // account/login/completed 通知を待機
            loginWaitTask = Task { [weak self] in
                await self?.waitForLoginCompletion(client: newClient, accountID: accountID)
            }
        } catch {
            if let client {
                await client.stop()
            }
            if pendingLoginAccountID == accountID {
                releasePendingLoginClient(for: accountID)
                try? accountStore.delete(accountID: accountID)
                loginFlow = .failed(errorMessage: error.localizedDescription)
            } else if !createdClient {
                loginFlow = .failed(errorMessage: error.localizedDescription)
            }
        }
    }

    private var pendingLoginClient: (any PendingLoginClient)?
    private var pendingLoginAccountID: UUID?
    private var loginWaitTask: Task<Void, Never>?

#if DEBUG
    func configureLoginTesting(
        clientFactory: @escaping PendingLoginClientFactory,
        openURL: @escaping LoginURLHandler
    ) {
        loginClientFactory = clientFactory
        loginURLHandler = openURL
    }
#endif

    private func releasePendingLoginClient(for accountID: UUID) {
        guard pendingLoginAccountID == accountID else { return }
        pendingLoginClient = nil
        pendingLoginAccountID = nil
        loginWaitTask = nil
    }

    private func waitForLoginCompletion(client: any PendingLoginClient, accountID: UUID) async {
        let stream = await client.notifications()
        for await notification in stream {
            guard !Task.isCancelled else { return }
            if notification.method == "account/login/completed" {
                let success = notification.params?.dictionary?["success"]?.boolValue ?? false
                let errorText = notification.params?.dictionary?["error"]?.stringValue
                await finishLogin(client: client, accountID: accountID, success: success, errorText: errorText)
                return
            }
        }
        guard !Task.isCancelled else { return }
        // 通知ストリームが終了した（プロセス終了など）
        await finishLogin(client: client, accountID: accountID, success: false, errorText: "app-server terminated")
    }

    private func finishLogin(client: any PendingLoginClient, accountID: UUID, success: Bool, errorText: String?) async {
        guard pendingLoginAccountID == accountID else {
            await client.stop()
            return
        }
        guard !Task.isCancelled else {
            await client.stop()
            return
        }
        if success {
            loginFlow = .completing
            do {
                let info = try await client.readAccount()
                guard pendingLoginAccountID == accountID, !Task.isCancelled else {
                    await client.stop()
                    return
                }
                let email = info.account?.email
                let plan = info.account?.planType
                let displayName = email ?? L("account.unnamed")
                let account = Account(
                    id: accountID,
                    displayName: displayName,
                    homeKind: .managed,
                    officialEmail: email,
                    officialPlanType: plan
                )
                let shouldSelectNewAccount = LoginAccountSelectionPolicy.shouldSelectNewAccount(
                    selectedAccountID: settingsStore.settings.selectedAccountID,
                    accounts: accounts,
                    snapshots: snapshots,
                    distributionChannel: distributionChannel,
                    placeholderDisplayName: L("account.default.name")
                )
                try accountStore.upsert(account)
                accounts = (try? accountStore.loadAccounts()) ?? accounts
                if shouldSelectNewAccount {
                    selectAccount(accountID)
                }
                loginFlow = .success(accountName: displayName)
                // ログイン直後に即時取得
                Task { await self.refreshAll(sendNotifications: false) }
            } catch {
                guard pendingLoginAccountID == accountID, !Task.isCancelled else {
                    await client.stop()
                    return
                }
                loginFlow = .failed(errorMessage: error.localizedDescription)
            }
        } else {
            // 失敗した場合は用意したホームを破棄
            try? accountStore.delete(accountID: accountID)
            loginFlow = .failed(errorMessage: errorText ?? "login failed")
        }
        await client.stop()
        if let codexProvider = provider as? CodexUsageProvider {
            await codexProvider.discardClient(for: accountID)
        }
        releasePendingLoginClient(for: accountID)
    }

    /// 保留中のログインをキャンセルする。
    public func cancelLogin() async {
        let capturedAccountID = pendingLoginAccountID
        loginWaitTask?.cancel()
        if let client = pendingLoginClient, let accountID = capturedAccountID {
            await client.stop()
            try? accountStore.delete(accountID: accountID)
        }
        if let capturedAccountID {
            guard pendingLoginAccountID == capturedAccountID else { return }
            releasePendingLoginClient(for: capturedAccountID)
        } else {
            guard pendingLoginAccountID == nil else { return }
        }
        loginFlow = .idle
    }

    public func resetLoginFlow() {
        loginFlow = .idle
    }

    public func deleteAccount(_ id: UUID) async {
        guard !isSampleMode, !pendingAccountDeletions.contains(id),
              let account = accounts.first(where: { $0.id == id }) else { return }
        accountDeletionErrorMessage = nil
        accountListRevision &+= 1
        accountRefreshRevision[id, default: 0] &+= 1
        pendingAccountDeletions.insert(id)
        defer {
            pendingAccountDeletions.remove(id)
            accountListRevision &+= 1
        }
        if distributionChannel.isAppStore && account.homeKind == .managed {
            do {
                guard let logoutProvider = provider as? any AccountLogoutProviding else {
                    throw CodexClientError.storeHelperMissing
                }
                try await logoutProvider.logoutAndStop(for: account)
                try Task.checkCancellation()
            } catch {
                // Do not expose RPC messages, auth URLs, or other raw error details.
                accountDeletionErrorMessage = L("settings.delete.logoutFailure")
                return
            }
        } else if let codexProvider = provider as? CodexUsageProvider {
            await codexProvider.discardClient(for: id)
        }
        do {
            try accountStore.delete(accountID: id)
        } catch {
            let failureKind: String
            switch error as? AccountStoreError {
            case .managedHomeOutsideContainer, .managedHomeRemovalFailed:
                failureKind = "managed-home"
            case .accountListPersistenceFailed:
                failureKind = "account-list"
            case nil:
                failureKind = "unknown"
            }
            logger.error("failed to delete account data: kind=\(failureKind)")
            accountDeletionErrorMessage = L("settings.delete.failure")
            return
        }
        snapshotStore.clearAccountData(accountID: id)
        accounts.removeAll { $0.id == id }
        snapshots.removeValue(forKey: id)
        var updatedSettings = settingsStore.settings
        updatedSettings.displayLimitByAccount.removeValue(forKey: id)
        if updatedSettings.selectedAccountID == id {
            updatedSettings.selectedAccountID = accounts.first?.id
        }
        settingsStore.settings = updatedSettings
        recomputeDisplayedState()
    }

    public func renameAccount(_ id: UUID, displayName: String) {
        guard !isSampleMode else { return }
        guard var account = accounts.first(where: { $0.id == id }) else { return }
        account.displayName = displayName.isEmpty ? (account.officialEmail ?? L("account.unnamed")) : displayName
        try? AccountStore.current.upsert(account)
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            accounts[index] = account
        }
    }
}
