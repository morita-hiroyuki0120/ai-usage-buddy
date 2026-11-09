import Foundation
// NSEvent の Sendable 準拠がSDK側で利用不可のため、ローカルモニタのクロージャ型で
// 診断が出るのを @preconcurrency で抑止する（実行時の動作には影響しない）
@preconcurrency import AppKit

// MARK: - Descriptor（純粋データ・テスト対象）

/// 右クリックメニューのアクション。
public enum MenuBarContextAction: Equatable, Sendable {
    case refreshNow
    case selectAccount(UUID)
    case rerunOnboarding
    case openSettings
    case checkForUpdates
    case quit
}

/// 右クリックメニューの項目。
public struct MenuBarContextItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case action(MenuBarContextAction)
        case submenu(titleKey: String, items: [MenuBarContextItem])
        case separator
    }

    public let kind: Kind
    /// 表示文字列（ローカライズ済み。アカウント名など動的な値を含む）。
    public let title: String?
    public let isEnabled: Bool
    /// チェックマーク表示（選択中アカウント等）。
    public let isChecked: Bool

    public init(kind: Kind, title: String? = nil, isEnabled: Bool = true, isChecked: Bool = false) {
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
        self.isChecked = isChecked
    }

    public static func separator() -> MenuBarContextItem {
        MenuBarContextItem(kind: .separator)
    }
}

/// モデル状態から右クリックメニューの構成を組み立てる（NSMenu非依存・テスト可能）。
public enum MenuBarContextMenuBuilder {

    public static func descriptor(
        accounts: [Account],
        selectedAccountID: UUID?,
        isRefreshing: Bool,
        includeUpdateCheck: Bool = true,
        localize: (String) -> String = { L($0) }
    ) -> [MenuBarContextItem] {
        var items: [MenuBarContextItem] = []

        // 今すぐ更新（更新中は無効化）
        items.append(MenuBarContextItem(
            kind: .action(.refreshNow),
            title: localize("context.refreshNow"),
            isEnabled: !isRefreshing
        ))

        // アカウント切り替え（サブメニュー）
        let accountItems: [MenuBarContextItem] = accounts.map { account in
            MenuBarContextItem(
                kind: .action(.selectAccount(account.id)),
                title: account.displayName,
                isChecked: account.id == selectedAccountID
            )
        }
        items.append(MenuBarContextItem(
            kind: .submenu(titleKey: "context.switchAccount", items: accountItems),
            title: localize("context.switchAccount"),
            isEnabled: !accountItems.isEmpty
        ))

        items.append(.separator())

        // セットアップ再実行
        items.append(MenuBarContextItem(
            kind: .action(.rerunOnboarding),
            title: localize("context.rerunOnboarding")
        ))

        // 設定
        items.append(MenuBarContextItem(
            kind: .action(.openSettings),
            title: localize("context.openSettings")
        ))

        if includeUpdateCheck {
            // 更新確認
            items.append(MenuBarContextItem(
                kind: .action(.checkForUpdates),
                title: localize("context.checkForUpdates")
            ))
        }

        items.append(.separator())

        // 終了
        items.append(MenuBarContextItem(
            kind: .action(.quit),
            title: localize("context.quit")
        ))

        return items
    }
}

// MARK: - NSMenu assembly

/// descriptor を NSMenu へ変換し、選択をハンドラへ流すコーディネータ。
@MainActor
final class MenuBarContextMenuCoordinator: NSObject {

    private let handler: (MenuBarContextAction) -> Void
    private var actions: [MenuBarContextAction] = []

    init(handler: @escaping (MenuBarContextAction) -> Void) {
        self.handler = handler
    }

    func makeMenu(from items: [MenuBarContextItem]) -> NSMenu {
        actions.removeAll()
        let menu = NSMenu()
        for item in items {
            menu.addItem(makeMenuItem(from: item))
        }
        return menu
    }

    private func makeMenuItem(from item: MenuBarContextItem) -> NSMenuItem {
        switch item.kind {
        case .separator:
            return NSMenuItem.separator()
        case .submenu(_, let subItems):
            let submenu = NSMenu()
            for subItem in subItems {
                submenu.addItem(makeMenuItem(from: subItem))
            }
            let menuItem = NSMenuItem(
                title: item.title ?? "",
                action: nil,
                keyEquivalent: ""
            )
            menuItem.submenu = submenu
            menuItem.isEnabled = item.isEnabled
            return menuItem
        case .action(let action):
            actions.append(action)
            let menuItem = NSMenuItem(
                title: item.title ?? "",
                action: #selector(performAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = actions.count - 1
            menuItem.isEnabled = item.isEnabled
            menuItem.state = item.isChecked ? .on : .off
            return menuItem
        }
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        handler(actions[sender.tag])
    }
}

// MARK: - Right click monitor

/// メニューバーアイコンの右クリックを検出する最小限のAppKitブリッジ。
/// MenuBarExtra(.window) とキャラクターアニメーションは維持したまま、
/// .rightMouseDown のみ横取りして NSMenu を表示する
/// （NSStatusItem への移行は行わない）。
/// ローカルイベントモニタは常にメインスレッドで呼ばれるため、
/// このクラスのメソッドもメインスレッドでのみ呼ぶ前提（NSEvent は Sendable ではない）。
final class MenuBarRightClickMonitor: NSObject {

    private var eventMonitor: Any?
    private var handler: (() -> Bool)?

    /// 右クリックがメニューバー自分のアイコン上だったときに呼ばれるハンドラ。
    /// メニューを表示して true を返すとイベントを consumed 扱いにする。
    func install(handler: @escaping () -> Bool) {
        self.handler = handler
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            self?.process(event) ?? event
        }
    }

    private func process(_ event: NSEvent) -> NSEvent? {
        guard Self.hitsOurStatusBarButton(event) else { return event }
        guard let handler, handler() else { return event }
        return nil
    }

    func uninstall() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        handler = nil
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    /// 右クリックが自分のNSStatusBarButton上で発生したか。
    /// 自プロセスのウィンドウ内の NSStatusBarButton は MenuBarExtra のものだけなので、
    /// ボタンの存在とヒットテストだけで自分のアイコンと判定できる。
    /// イベントの window が結びつかない経路で届く場合に備え、
    /// マウス位置と全ウィンドウのステータスボタン画面矩形によるフォールバックも持つ。
    static func hitsOurStatusBarButton(_ event: NSEvent) -> Bool {
        if let window = event.window,
           let contentView = window.contentView,
           let button = firstStatusBarButton(in: contentView) {
            let buttonFrameInWindow = button.convert(button.bounds, to: contentView)
            if buttonFrameInWindow.contains(event.locationInWindow) {
                return true
            }
        }
        return anyStatusBarButtonContainsScreenPoint(NSEvent.mouseLocation)
    }

    /// 自プロセスのいずれかのウィンドウにあるステータスボタンが画面座標の点を含むか。
    private static func anyStatusBarButtonContainsScreenPoint(_ point: NSPoint) -> Bool {
        for window in NSApp.windows {
            guard let contentView = window.contentView,
                  let button = firstStatusBarButton(in: contentView) else {
                continue
            }
            let frameInWindow = button.convert(button.bounds, to: nil)
            let screenFrame = window.convertToScreen(frameInWindow)
            if screenFrame.contains(point) {
                return true
            }
        }
        return false
    }

    private static func firstStatusBarButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let found = firstStatusBarButton(in: subview) {
                return found
            }
        }
        return nil
    }
}
