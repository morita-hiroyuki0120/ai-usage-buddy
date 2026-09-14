import Foundation
import AppKit
import Testing
@testable import AIUsageBuddy

/// グローバルショートカットの保存・復元・競合・解除、
/// クイック表示（PopoverView共有）、手動更新のテスト。
/// HotKeyCallbackStore（静的）を経由するテストがあるため直列実行する。
@Suite(.serialized)
@MainActor
struct GlobalShortcutTests {

    @Test("初期値は ⌃⌥U と ⌃⌥R")
    func defaultShortcutSpecs() {
        let show = HotKeySpec.defaultShowUsage
        #expect(show.keyCode == 32, "kVK_ANSI_U")
        #expect(show.modifiers == CarbonModifier.control + CarbonModifier.option)
        #expect(show.displayText == "⌃⌥U")

        let refresh = HotKeySpec.defaultRefresh
        #expect(refresh.keyCode == 15, "kVK_ANSI_R")
        #expect(refresh.displayText == "⌃⌥R")
    }

    @Test("ショートカットは設定として保存・復元される")
    func shortcutRoundTrip() {
        let env = TestEnvironment.make()
        let customShow = HotKeySpec(keyCode: 1 /* S */, modifiers: CarbonModifier.control + CarbonModifier.option)
        let customRefresh = HotKeySpec(keyCode: 11 /* B */, modifiers: CarbonModifier.cmd + CarbonModifier.option)

        env.model.updateShortcuts(show: customShow, refresh: customRefresh)
        #expect(env.model.settingsStore.settings.showUsageShortcut == customShow)
        #expect(env.model.settingsStore.settings.refreshShortcut == customRefresh)

        // settings.json を経由した復元
        let reloaded = SettingsStore(containerDirectory: env.container)
        #expect(reloaded.settings.showUsageShortcut == customShow)
        #expect(reloaded.settings.refreshShortcut == customRefresh)
    }

    @Test("適用でホットキー登録される（Carbon登録の引数も検証）")
    func applyRegistersHotKeys() {
        let env = TestEnvironment.make()
        env.model.updateShortcuts(show: .defaultShowUsage, refresh: .defaultRefresh)

        let show = env.shortcutRegistrar.registerCalls.first { $0.id == GlobalShortcutManager.showUsageHotKeyID }
        #expect(show?.keyCode == HotKeySpec.defaultShowUsage.keyCode)
        #expect(show?.modifiers == HotKeySpec.defaultShowUsage.modifiers)

        let refresh = env.shortcutRegistrar.registerCalls.first { $0.id == GlobalShortcutManager.refreshHotKeyID }
        #expect(refresh?.keyCode == HotKeySpec.defaultRefresh.keyCode)
        #expect(env.model.shortcutManager.validationIssues.isEmpty)
        #expect(env.model.shortcutManager.failedShortcutNames.isEmpty)
    }

    @Test("競合（同一キー）は検証エラーになり登録されない")
    func duplicateSpecsRejected() {
        let env = TestEnvironment.make()
        let same = HotKeySpec(keyCode: 32, modifiers: CarbonModifier.control + CarbonModifier.option)
        env.model.updateShortcuts(show: same, refresh: same)

        #expect(env.model.shortcutManager.validationIssues.contains(.duplicateSpecs))
        #expect(env.shortcutRegistrar.activeIDs.isEmpty, "検証失敗時は登録が残らない")
    }

    @Test("修飾キー無し・キー無しは検証エラー")
    func invalidSpecsRejected() {
        #expect(ShortcutValidator.issues(
            show: HotKeySpec(keyCode: 32, modifiers: 0),
            refresh: .defaultRefresh
        ).contains(.missingModifiers))

        #expect(ShortcutValidator.issues(
            show: HotKeySpec(keyCode: -1, modifiers: CarbonModifier.cmd),
            refresh: .defaultRefresh
        ).contains(.missingKey))

        // 両方無効（enabled=false）なら検証エラーにならない
        #expect(ShortcutValidator.issues(
            show: HotKeySpec(keyCode: 32, modifiers: 0, enabled: false),
            refresh: HotKeySpec(keyCode: -1, modifiers: 0, enabled: false)
        ).isEmpty)
    }

    @Test("無効化すると登録が解除される")
    func disablingUnregisters() {
        let env = TestEnvironment.make()
        env.model.updateShortcuts(show: .defaultShowUsage, refresh: .defaultRefresh)
        #expect(env.shortcutRegistrar.activeIDs.count == 2)

        var disabled = HotKeySpec.defaultShowUsage
        disabled.enabled = false
        env.model.updateShortcuts(show: disabled, refresh: .defaultRefresh)

        #expect(env.shortcutRegistrar.unregisteredIDs.contains(GlobalShortcutManager.showUsageHotKeyID))
        #expect(!env.shortcutRegistrar.activeIDs.contains(GlobalShortcutManager.showUsageHotKeyID))
        #expect(env.shortcutRegistrar.activeIDs.contains(GlobalShortcutManager.refreshHotKeyID), "もう片方は維持")
        // 設定にも保存される
        #expect(env.model.settingsStore.settings.showUsageShortcut.enabled == false)
    }

    @Test("登録失敗は設定UIに表示される")
    func registrationFailureSurfaced() {
        let env = TestEnvironment.make()
        env.shortcutRegistrar.shouldFail = true
        env.model.updateShortcuts(show: .defaultShowUsage, refresh: .defaultRefresh)

        #expect(env.model.shortcutManager.failedShortcutNames.count == 2)
        #expect(env.model.shortcutManager.failedShortcutNames.contains("shortcut.name.showUsage"))
    }

    @Test("初期値復元はデフォルトへ戻す")
    func restoreDefaults() {
        let env = TestEnvironment.make()
        let custom = HotKeySpec(keyCode: 1, modifiers: CarbonModifier.cmd)
        env.model.updateShortcuts(show: custom, refresh: custom)
        #expect(!env.model.shortcutManager.validationIssues.isEmpty)

        env.model.updateShortcuts(show: .defaultShowUsage, refresh: .defaultRefresh)
        #expect(env.model.settingsStore.settings.showUsageShortcut == .defaultShowUsage)
        #expect(env.model.shortcutManager.validationIssues.isEmpty)
        #expect(env.shortcutRegistrar.activeIDs.count == 2)
    }

    @Test("NSEvent修飾キーからCarbonフラグへの変換")
    func carbonModifierConversion() {
        let flags: NSEvent.ModifierFlags = [.control, .option]
        #expect(GlobalShortcutManager.carbonModifiers(from: flags) == CarbonModifier.control + CarbonModifier.option)
        #expect(GlobalShortcutManager.carbonModifiers(from: [.command]) == CarbonModifier.cmd)
        #expect(GlobalShortcutManager.carbonModifiers(from: []) == 0)
    }

    // MARK: - クイック利用状況ウインドウ

    @Test("クイック表示は PopoverView を共有してトグル動作する")
    func quickUsageTogglesWithSharedPopoverView() {
        let env = TestEnvironment.make()
        let quickShows = env.windowHost.showCalls.filter { $0.kind == .quickUsage }
        #expect(quickShows.isEmpty)

        env.model.toggleQuickUsageWindow()

        let shown = env.windowHost.showCalls.filter { $0.kind == .quickUsage }
        #expect(shown.count == 1)
        #expect(shown[0].contentDescription.contains("PopoverView"), "ポップオーバーと同じViewを使う")

        // トグルで閉じる
        env.model.toggleQuickUsageWindow()
        #expect(env.windowHost.closeCalls.contains(.quickUsage))
    }

    @Test("表示ショートカットの発火でクイック表示がトグルする")
    func showUsageShortcutTogglesWindow() async {
        let env = TestEnvironment.make()
        env.model.applyShortcutSettings()

        // Carbon コールバック経路（MainActor配送）をシミュレートする
        env.model.shortcutManager.onShowUsage?()
        #expect(env.windowHost.showCalls.contains { $0.kind == .quickUsage })
    }

    @Test("ホットキーコールバックはMainActorへ配送されてトグルする")
    func hotKeyCallbackDispatchesToMainActor() async throws {
        let env = TestEnvironment.make()
        env.model.applyShortcutSettings()

        // Carbon の C 関数ポインタから呼ばれるのと同じ経路
        HotKeyCallbackStore.dispatch(id: GlobalShortcutManager.showUsageHotKeyID)
        // MainActorへのTask配送を待つ
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(env.windowHost.showCalls.contains { $0.kind == .quickUsage })
    }

    // MARK: - 手動更新

    @Test("手動更新は取得を実行して完了する")
    func manualRefreshFetches() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let snapshot = UsageSnapshot(
            accountID: account.id,
            fiveHour: QuotaWindow(kind: .fiveHour, remainingPercent: 42, resetAt: Date().addingTimeInterval(3600), fetchedAt: Date(), state: .fresh),
            weekly: QuotaWindow(kind: .weekly, remainingPercent: 66, resetAt: Date().addingTimeInterval(86400), fetchedAt: Date(), state: .fresh),
            fetchedAt: Date()
        )
        let env = TestEnvironment.make(accounts: [account], snapshots: [snapshot])
        let before = env.provider.fetchCallCount

        await env.model.manualRefresh()

        #expect(env.provider.fetchCallCount == before + 1, "取得が1回走る")
        #expect(!env.model.isRefreshing, "完了後は更新中でない")
        #expect(env.model.lastRefreshCompletedAt != nil)
        #expect(env.model.snapshots[account.id]?.fiveHour?.remainingPercent == 42)
    }

    @Test("更新ショートカットの発火で手動更新される")
    func refreshShortcutTriggersManualRefresh() async throws {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let snapshot = UsageSnapshot(
            accountID: account.id,
            fiveHour: QuotaWindow(kind: .fiveHour, remainingPercent: 42, resetAt: Date().addingTimeInterval(3600), fetchedAt: Date(), state: .fresh),
            weekly: nil,
            fetchedAt: Date()
        )
        let env = TestEnvironment.make(accounts: [account], snapshots: [snapshot])
        env.model.applyShortcutSettings()
        let before = env.provider.fetchCallCount

        HotKeyCallbackStore.dispatch(id: GlobalShortcutManager.refreshHotKeyID)
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(env.provider.fetchCallCount > before, "ショートカットから手動更新が走る")
    }
}
