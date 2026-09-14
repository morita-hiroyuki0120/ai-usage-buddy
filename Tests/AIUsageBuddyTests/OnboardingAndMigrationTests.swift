import Foundation
import Testing
@testable import AIUsageBuddy

/// 初回セットアップの表示・スキップ・再実行、既存ユーザー移行、
/// 通知許可の要求タイミング、自動起動の明示確認のテスト。
@Suite
@MainActor
struct OnboardingAndMigrationTests {

    // MARK: - 新規インストール判定とセットアップ表示

    @Test("新規インストールでは初回セットアップが表示待ちになる")
    func freshInstallMarksOnboardingPending() {
        let env = TestEnvironment.makeFreshInstall()
        #expect(env.model.onboardingPending, "新規インストールは初回セットアップ待ち")
        #expect(!env.model.onboardingActive, "表示はまだ")
        // 未接続でも通常利用できる: 既定アカウントが自動作成される
        #expect(!env.model.accounts.isEmpty, "既定アカウントが自動作成される")
    }

    @Test("startOnboardingでウィンドウ表示・ステップは歓迎から")
    func startOnboardingShowsWindowAtWelcome() {
        let env = TestEnvironment.makeFreshInstall()
        env.model.startOnboarding()

        #expect(env.model.onboardingActive)
        #expect(env.model.onboardingStep == .welcome)
        #expect(env.windowHost.showCalls.contains { $0.kind == .onboarding }, "オンボーディングウィンドウが表示される")
    }

    @Test("スキップすると完了扱いになり再表示しない")
    func skipMarksCompleted() {
        let env = TestEnvironment.makeFreshInstall()
        env.model.startOnboarding()
        env.model.skipOnboarding()

        #expect(env.model.settingsStore.settings.onboardingCompleted, "スキップでも完了扱い")
        #expect(env.model.settingsStore.settings.onboardingVersion == OnboardingFlow.currentVersion)
        #expect(!env.model.onboardingPending)
        #expect(!env.model.onboardingActive)
        #expect(env.windowHost.closeCalls.contains(.onboarding), "ウィンドウが閉じられる")

        // 完了後の起動相当で再表示しない（新規インストール判定でも pending にならない）
        #expect(!env.model.onboardingPending)
    }

    @Test("全ステップ進めると完了する（5段階）")
    func advancingThroughAllStepsCompletes() {
        let env = TestEnvironment.makeFreshInstall()
        env.model.startOnboarding()

        let steps: [OnboardingStep] = [.welcome, .connect, .notifications, .loginItem, .usageGuide]
        for (index, step) in steps.enumerated() {
            #expect(env.model.onboardingStep == step, "ステップ\(index)は\(step)")
            env.model.advanceOnboarding()
        }

        #expect(env.model.settingsStore.settings.onboardingCompleted)
        #expect(!env.model.onboardingActive)
        #expect(env.windowHost.closeCalls.contains(.onboarding))
    }

    @Test("設定・右クリックから再実行できる（完了後も）")
    func rerunOnboardingAfterCompletion() {
        let env = TestEnvironment.makeFreshInstall()
        env.model.skipOnboarding()
        #expect(!env.model.onboardingActive)

        env.model.startOnboarding()
        #expect(env.model.onboardingActive)
        #expect(env.model.onboardingStep == .welcome)
        #expect(env.windowHost.showCalls.contains { $0.kind == .onboarding })
    }

    @Test("右クリックメニューのセットアップ再実行アクションが機能する")
    func contextMenuRerunAction() {
        let env = TestEnvironment.make()
        env.model.handleMenuBarContextAction(.rerunOnboarding)
        #expect(env.model.onboardingActive)
        #expect(env.windowHost.showCalls.contains { $0.kind == .onboarding })
    }

    // MARK: - 既存ユーザー移行

    @Test("既存インストールには初回セットアップを表示しない（完了扱いへ移行）")
    func existingInstallSkipsOnboarding() {
        let account = Account(displayName: "既存", homeKind: .defaultHome)
        let env = TestEnvironment.make(accounts: [account])

        #expect(!env.model.onboardingPending, "既存ユーザーはセットアップ待ちにならない")
        #expect(env.model.settingsStore.settings.onboardingCompleted, "完了扱いへ移行される")
        #expect(env.model.settingsStore.settings.onboardingVersion == OnboardingFlow.currentVersion)
    }

    @Test("インストール判定はファイルの存在で行う")
    func installDetectorUsesMarkerFiles() throws {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AIUsageBuddyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        #expect(InstallDetector.detect(container: container) == .freshInstall, "空は新規")

        for marker in ["settings.json", "accounts.json", "snapshots.json"] {
            let target = container.appendingPathComponent(marker)
            try? FileManager.default.removeItem(at: target)
            try Data("{}".utf8).write(to: target)
            #expect(
                InstallDetector.detect(container: container) == .existingInstall,
                "\(marker) があれば既存"
            )
            try FileManager.default.removeItem(at: target)
        }
    }

    @Test("旧settings.json（新キー欠落）は既定値で読み込まれスキーマv2へ移行される")
    func legacySettingsDecodeAndMigration() throws {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AIUsageBuddyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        // v1世代: 新しいキーが一切無い
        // （displayLimitByAccount は [UUID: Kind] のCodable表現である配列形式）
        let legacyJSON = """
        {
          "selectedAccountID" : null,
          "displayLimitByAccount" : [],
          "notificationsEnabled" : true,
          "notificationThresholds" : [20, 10],
          "languageOverride" : null,
          "autoRefreshInterval" : 60,
          "launchAtLogin" : false
        }
        """
        try Data(legacyJSON.utf8).write(to: container.appendingPathComponent("settings.json"))

        let store = SettingsStore(containerDirectory: container)
        // 既存ユーザー設定は壊れていない
        #expect(store.settings.notificationThresholds == [20, 10])
        #expect(store.settings.notificationsEnabled)
        // 新キーは既定値
        #expect(!store.settings.onboardingCompleted)
        #expect(store.settings.showUsageShortcut == .defaultShowUsage)
        #expect(store.settings.refreshShortcut == .defaultRefresh)
        #expect(store.settings.automaticUpdateChecksEnabled)
        // スキーマバージョンは現行へ移行されて保存される
        #expect(store.settings.schemaVersion == AppSettings.currentSchemaVersion)
        let saved = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(contentsOf: container.appendingPathComponent("settings.json"))
        )
        #expect(saved.schemaVersion == AppSettings.currentSchemaVersion)

        // 既存値を保護したまま新キーを保存できる
        store.settings.launchAtLogin = true
        let reloaded = SettingsStore(containerDirectory: container)
        #expect(reloaded.settings.launchAtLogin)
        #expect(reloaded.settings.notificationThresholds == [20, 10])
    }

    // MARK: - 通知許可の要求タイミング

    @Test("初回セットアップ待ちの間は起動時に通知許可を要求しない")
    func noAuthorizationRequestWhileOnboardingPending() async {
        let env = TestEnvironment.makeFreshInstall()
        #expect(env.model.onboardingPending)

        await env.model.performStartupActions()

        #expect(!env.spy.authorizationRequested, "セットアップの通知ステップで明示的に要求するまで出さない")
    }

    @Test("セットアップの通知ステップでのみ明示的に要求する")
    func authorizationRequestedFromOnboardingStep() async {
        let env = TestEnvironment.makeFreshInstall()
        #expect(!env.spy.authorizationRequested)

        await env.model.requestNotificationAuthorizationFromOnboarding()
        #expect(env.spy.authorizationRequested)
    }

    @Test("既存ユーザーは起動時に要求する（既に判定済みならプロンプトは出ない）")
    func existingUserRequestsAtStartup() async {
        let account = Account(displayName: "既存", homeKind: .defaultHome)
        let env = TestEnvironment.make(accounts: [account])
        #expect(env.model.settingsStore.settings.notificationsEnabled)

        await env.model.performStartupActions()
        #expect(env.spy.authorizationRequested)
    }

    // MARK: - 自動起動の明示確認

    @Test("初期化・起動・セットアップ開始だけではログイン項目を登録しない")
    func noImplicitLoginItemRegistration() async {
        let env = TestEnvironment.makeFreshInstall()
        env.model.startOnboarding()
        env.model.advanceOnboarding()
        env.model.advanceOnboarding()

        #expect(env.loginItemSpy.registerCount == 0, "明示操作なしに登録しない")
        #expect(env.loginItemSpy.unregisterCount == 0)
        #expect(!env.model.settingsStore.settings.launchAtLogin)
    }

    @Test("明示的な操作でのみ登録・解除される")
    func explicitRegistrationOnly() {
        let env = TestEnvironment.makeFreshInstall()

        env.model.setLaunchAtLogin(true)
        #expect(env.loginItemSpy.registerCount == 1)
        #expect(env.model.settingsStore.settings.launchAtLogin)
        #expect(env.model.launchAtLoginError == nil)

        env.model.setLaunchAtLogin(false)
        #expect(env.loginItemSpy.unregisterCount == 1)
        #expect(!env.model.settingsStore.settings.launchAtLogin)
    }

    @Test("登録失敗時はエラー表示と実状態へ同期する")
    func loginItemFailureSurfacesError() {
        let env = TestEnvironment.makeFreshInstall()
        env.loginItemSpy.shouldFail = true

        env.model.setLaunchAtLogin(true)
        #expect(env.model.launchAtLoginError != nil)
        #expect(!env.model.settingsStore.settings.launchAtLogin, "失敗時は実状態（未登録）を反映")
    }
}
