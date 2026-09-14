import Foundation
import AppKit
import Testing
@testable import AIUsageBuddy

/// メニューバー右クリックメニューの構成とアクションのテスト。
/// （実際のNSMenu表示はUI依存のため、純粋なdescriptorとモデル統合を検証する）
@Suite
@MainActor
struct MenuBarContextMenuTests {

    private func localize(_ key: String) -> String { key }

    @Test("項目の並びは仕様どおり: 更新/アカウント/セットアップ/設定/更新確認/終了")
    func itemOrderMatchesSpec() {
        let a = Account(displayName: "A", homeKind: .defaultHome)
        let b = Account(displayName: "B", homeKind: .managed)
        let items = MenuBarContextMenuBuilder.descriptor(
            accounts: [a, b],
            selectedAccountID: a.id,
            isRefreshing: false,
            localize: localize
        )

        // 先頭は今すぐ更新
        guard case .action(.refreshNow)? = items.first?.kind else {
            Issue.record("先頭は今すぐ更新であること")
            return
        }
        // 2番目はアカウント切り替えサブメニュー
        guard case .submenu("context.switchAccount", let subItems)? = items.dropFirst().first?.kind else {
            Issue.record("2番目はアカウント切り替えサブメニューであること")
            return
        }
        #expect(subItems.count == 2)
        #expect(subItems[0].title == "A")
        #expect(subItems[0].isChecked, "選択中アカウントにチェック")
        #expect(subItems[1].title == "B")
        #expect(!subItems[1].isChecked)

        // 残りのアクション種別（セパレータを除いた順序）
        var actions: [MenuBarContextAction] = []
        var separators = 0
        for item in items {
            switch item.kind {
            case .action(let action): actions.append(action)
            case .submenu: break
            case .separator: separators += 1
            }
        }
        #expect(actions == [
            .refreshNow,
            .rerunOnboarding,
            .openSettings,
            .checkForUpdates,
            .quit,
        ])
        #expect(separators == 2)
    }

    @Test("更新中は今すぐ更新を無効化する")
    func refreshDisabledWhileRefreshing() {
        let a = Account(displayName: "A", homeKind: .defaultHome)
        let items = MenuBarContextMenuBuilder.descriptor(
            accounts: [a],
            selectedAccountID: a.id,
            isRefreshing: true,
            localize: localize
        )
        #expect(items.first?.isEnabled == false, "更新中は無効")
    }

    @Test("アカウントが無いときはアカウント切り替えを無効化する")
    func switchAccountDisabledWithoutAccounts() {
        let items = MenuBarContextMenuBuilder.descriptor(
            accounts: [],
            selectedAccountID: nil,
            isRefreshing: false,
            localize: localize
        )
        guard case .submenu = items.dropFirst().first?.kind else {
            Issue.record("サブメニューがあること")
            return
        }
        #expect(items.dropFirst().first?.isEnabled == false)
    }

    @Test("メニュー文言は日英ともに定義されている")
    func localizationKeysExist() {
        let manager = LocalizationManager(defaults: UserDefaults(suiteName: "test-loc-\(UUID().uuidString)")!)
        let keys = [
            "context.refreshNow", "context.switchAccount", "context.rerunOnboarding",
            "context.openSettings", "context.checkForUpdates", "context.quit",
        ]
        for key in keys {
            for language in AppLanguage.allCases {
                #expect(manager.string(key: key, language: language) != key, "\(language.rawValue): \(key)")
            }
        }
    }

    // MARK: - アクション統合

    @Test("アカウント切り替えアクションで選択が変わる")
    func selectAccountActionSwitchesSelection() async {
        let accountA = Account(displayName: "A", homeKind: .defaultHome)
        let accountB = Account(displayName: "B", homeKind: .managed)
        let snapshotA = UsageSnapshot(
            accountID: accountA.id,
            fiveHour: QuotaWindow(kind: .fiveHour, remainingPercent: 80, resetAt: Date().addingTimeInterval(3600), fetchedAt: Date(), state: .fresh),
            fetchedAt: Date()
        )
        let snapshotB = UsageSnapshot(
            accountID: accountB.id,
            fiveHour: QuotaWindow(kind: .fiveHour, remainingPercent: 15, resetAt: Date().addingTimeInterval(3600), fetchedAt: Date(), state: .fresh),
            fetchedAt: Date()
        )
        let env = TestEnvironment.make(accounts: [accountA, accountB], snapshots: [snapshotA, snapshotB])
        await env.model.refreshAll(sendNotifications: false)

        env.model.handleMenuBarContextAction(.selectAccount(accountB.id))

        #expect(env.model.selectedAccount?.id == accountB.id)
        #expect(env.model.displayedPercent == 15, "切り替え後の表示も変わる")
    }

    @Test("今すぐ更新アクションで取得が走る")
    func refreshNowActionFetches() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let snapshot = UsageSnapshot(
            accountID: account.id,
            fiveHour: QuotaWindow(kind: .fiveHour, remainingPercent: 50, resetAt: Date().addingTimeInterval(3600), fetchedAt: Date(), state: .fresh),
            fetchedAt: Date()
        )
        let env = TestEnvironment.make(accounts: [account], snapshots: [snapshot])
        let before = env.provider.fetchCallCount

        env.model.handleMenuBarContextAction(.refreshNow)
        // 非同期Taskの完了を待つ
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(env.provider.fetchCallCount > before)
    }

    @Test("設定アクションで設定ウィンドウが開く")
    func openSettingsActionOpensWindow() {
        let env = TestEnvironment.make()
        env.model.handleMenuBarContextAction(.openSettings)
        #expect(env.windowHost.showCalls.contains { $0.kind == .settings })
    }

    // MARK: - 右クリックのヒットテスト（AppKit幾何検証）

    /// 実際の NSStatusBarButton を持つウィンドウでヒットテストの幾何を検証する。
    /// （合成マウスイベントがメニューバーへ届かない環境制限のため、
    ///   監視の取り付けは実機確認、幾何ロジックはここで保証する）
    @Test("右クリック判定は自分のステータスバーボタン上のみtrue")
    func hitTestDetectsOwnStatusBarButton() throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        guard let button = statusItem.button, let window = button.window else {
            Issue.record("テスト用ステータスアイテムのボタン/ウィンドウが取得できない")
            return
        }
        let frame = button.convert(button.bounds, to: window.contentView)
        let center = CGPoint(x: frame.midX, y: frame.midY)

        func makeEvent(at location: CGPoint, windowNumber: Int) -> NSEvent? {
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        }

        // ボタン上のイベントは true
        let inside = try #require(makeEvent(at: center, windowNumber: window.windowNumber))
        #expect(MenuBarRightClickMonitor.hitsOurStatusBarButton(inside))

        // ウィンドウ内のボタン外は false（フォールバックもマウス位置で判定）
        let farOutside = CGPoint(x: frame.maxX + 500, y: frame.maxY + 300)
        let outside = try #require(makeEvent(at: farOutside, windowNumber: window.windowNumber))
        #expect(!MenuBarRightClickMonitor.hitsOurStatusBarButton(outside))
    }
}
