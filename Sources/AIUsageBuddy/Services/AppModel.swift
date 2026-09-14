import Foundation
import Combine
import AppKit
import SwiftUI

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

    public let settingsStore: SettingsStore
    public let snapshotStore: SnapshotStore
    public let accountStore: AccountStore
    public let localization: LocalizationManager
    public let updateService: UpdateService
    public let shortcutManager: GlobalShortcutManager
    public let windowPresenter: AppWindowPresenter
    private let notificationCenter: any NotificationScheduling
    private let loginItemManager: any LoginItemManaging

    private let provider: UsageProvider
    private let stateMachine = CharacterStateMachine()
    /// accountID|limit ごとの直前キャラクター状態（ヒステリシス用）。
    private var lastCharacterStates: [String: CharacterState] = [:]
    private var autoRefreshTask: Task<Void, Never>?
    private let logger = AppLogger(category: "AppModel")

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
        shortcutManager: GlobalShortcutManager? = nil
    ) {
        self.provider = provider ?? CodexUsageProvider.shared
        self.settingsStore = settingsStore ?? SettingsStore.shared
        self.snapshotStore = snapshotStore ?? SnapshotStore.shared
        self.accountStore = accountStore ?? AccountStore.current
        self.notificationCenter = notificationScheduler ?? NotificationScheduler.shared
        self.localization = localization ?? LocalizationManager.shared
        self.loginItemManager = loginItemManager ?? SMAppServiceLoginItemManager()
        self.updateService = updateService ?? UpdateService()
        self.windowPresenter = windowPresenter ?? AppWindowPresenter()
        self.shortcutManager = shortcutManager ?? GlobalShortcutManager()

        // 既定アカウントを自動作成する前に、新規インストールか既存かを判定する
        // （accounts.json は自動作成で即座に書かれるため、判定が先）。
        let installStatus = InstallDetector.detect(container: self.settingsStore.containerDirectory)

        loadPersistedState()

        // 初回起動時にアカウントが無ければ既定のCodexホームを参照するアカウントを自動作成する
        if accounts.isEmpty {
            let account = Account(displayName: L("account.default.name"), homeKind: .defaultHome)
            if (try? self.accountStore.upsert(account)) != nil {
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
        await updateService.automaticCheckIfNeeded(
            enabled: settingsStore.settings.automaticUpdateChecksEnabled
        )
    }

    public func stop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        shortcutManager.unregisterAll()
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshCompletedAt = Date()
        }

        // アカウント一覧を再読み込み（設定画面での追加・削除に追従）
        if let loaded = try? await provider.accounts() {
            accounts = loaded
        }

        for account in accounts {
            do {
                // 公式識別情報も更新（表示名の元など）
                if let updated = try? await provider.fetchAccountInfo(for: account) {
                    if let index = accounts.firstIndex(where: { $0.id == updated.id }) {
                        // ユーザー設定の表示名を保持しつつ公式情報のみ反映
                        var merged = accounts[index]
                        merged.officialEmail = updated.officialEmail
                        merged.officialPlanType = updated.officialPlanType
                        accounts[index] = merged
                        try? accountStore.upsert(merged)
                    }
                }
                let snapshot = try await provider.fetchSnapshot(for: account)
                snapshotStore.storeOfficialSnapshot(snapshot)
                snapshots[account.id] = snapshot
            } catch {
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

    /// 手動更新ボタンからの取得。
    public func manualRefresh() async {
        await refreshAll(sendNotifications: true)
    }

    // MARK: - Character state

    /// 選択中アカウント＋表示リミットに基づいてキャラクター状態と残量を再計算する。
    public func recomputeDisplayedState() {
        guard let selectedID = settingsStore.settings.selectedAccountID,
              let snapshot = snapshots[selectedID] else {
            characterState = .unknown
            displayedPercent = nil
            return
        }
        let limit = settingsStore.displayLimit(for: selectedID)
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
        guard let id = settingsStore.settings.selectedAccountID else { return nil }
        return accounts.first { $0.id == id }
    }

    public func selectAccount(_ id: UUID) {
        settingsStore.settings.selectedAccountID = id
        selectedDisplayLimit = settingsStore.displayLimit(for: id)
        // 表示コンテキストが変わるためキャラクター状態はバンドから再導出する
        recomputeDisplayedState()
    }

    public func setDisplayLimit(_ limit: QuotaLimitKind, for accountID: UUID) {
        settingsStore.setDisplayLimit(limit, for: accountID)
        if settingsStore.settings.selectedAccountID == accountID {
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
            settingsStore.settings.selectedAccountID,
            isRefreshing
        )
    }

    // MARK: - Manual override

    public func setManualOverride(accountID: UUID, kind: QuotaLimitKind, percent: Int) {
        snapshotStore.setManualOverride(accountID: accountID, kind: kind, percent: percent)
        snapshots[accountID] = snapshotStore.snapshot(for: accountID)
        recomputeDisplayedState()
    }

    public func clearManualOverride(accountID: UUID, kind: QuotaLimitKind) {
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
            await notificationCenter.sendLowUsageNotification(decision, language: language)
            snapshotStore.markNotified(key: decision.key)
        }
    }

    // MARK: - Account management

    /// 新規アカウント追加: 公式OAuthログインフローを開始する。
    public func beginAddAccount() async {
        let accountID = UUID()
        do {
            let home = try accountStore.prepareManagedHome(for: accountID)
            let client = CodexAppServerClient(codexHome: home)
            try await client.start()
            let login = try await client.startLogin()
            guard let authURL = login.authUrl else {
                loginFlow = .failed(errorMessage: "app-server did not return an authUrl")
                await client.stop()
                return
            }
            pendingLoginClient = client
            pendingLoginAccountID = accountID
            loginFlow = .awaitingBrowserAuth(authURL: authURL)
            if let url = URL(string: authURL) {
                NSWorkspace.shared.open(url)
            }
            // account/login/completed 通知を待機
            loginWaitTask = Task { [weak self] in
                await self?.waitForLoginCompletion(client: client, accountID: accountID)
            }
        } catch {
            loginFlow = .failed(errorMessage: error.localizedDescription)
        }
    }

    private var pendingLoginClient: CodexAppServerClient?
    private var pendingLoginAccountID: UUID?
    private var loginWaitTask: Task<Void, Never>?

    private func waitForLoginCompletion(client: CodexAppServerClient, accountID: UUID) async {
        let stream = await client.notifications()
        for await notification in stream {
            if notification.method == "account/login/completed" {
                let success = notification.params?.dictionary?["success"]?.boolValue ?? false
                let errorText = notification.params?.dictionary?["error"]?.stringValue
                await finishLogin(client: client, accountID: accountID, success: success, errorText: errorText)
                return
            }
        }
        // 通知ストリームが終了した（プロセス終了など）
        await finishLogin(client: client, accountID: accountID, success: false, errorText: "app-server terminated")
    }

    private func finishLogin(client: CodexAppServerClient, accountID: UUID, success: Bool, errorText: String?) async {
        guard pendingLoginAccountID == accountID else { return }
        defer {
            pendingLoginClient = nil
            pendingLoginAccountID = nil
        }
        if success {
            loginFlow = .completing
            do {
                let info = try await client.readAccount()
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
                try accountStore.upsert(account)
                accounts = (try? accountStore.loadAccounts()) ?? accounts
                if settingsStore.settings.selectedAccountID == nil {
                    settingsStore.settings.selectedAccountID = accountID
                }
                loginFlow = .success(accountName: displayName)
                // ログイン直後に即時取得
                Task { await self.refreshAll(sendNotifications: false) }
            } catch {
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
    }

    /// 保留中のログインをキャンセルする。
    public func cancelLogin() async {
        loginWaitTask?.cancel()
        if let client = pendingLoginClient, let accountID = pendingLoginAccountID {
            await client.stop()
            try? accountStore.delete(accountID: accountID)
        }
        pendingLoginClient = nil
        pendingLoginAccountID = nil
        loginFlow = .idle
    }

    public func resetLoginFlow() {
        loginFlow = .idle
    }

    public func deleteAccount(_ id: UUID) async {
        if let codexProvider = provider as? CodexUsageProvider {
            await codexProvider.discardClient(for: id)
        }
        try? accountStore.delete(accountID: id)
        accounts = (try? accountStore.loadAccounts()) ?? accounts
        snapshots.removeValue(forKey: id)
        if settingsStore.settings.selectedAccountID == id {
            settingsStore.settings.selectedAccountID = accounts.first?.id
        }
        recomputeDisplayedState()
    }

    public func renameAccount(_ id: UUID, displayName: String) {
        guard var account = accounts.first(where: { $0.id == id }) else { return }
        account.displayName = displayName.isEmpty ? (account.officialEmail ?? L("account.unnamed")) : displayName
        try? AccountStore.current.upsert(account)
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            accounts[index] = account
        }
    }
}
