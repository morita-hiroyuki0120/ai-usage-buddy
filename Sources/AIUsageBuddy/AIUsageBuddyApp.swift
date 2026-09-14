import SwiftUI
import AppKit

/// アプリ全体で共有する AppModel を保持するコンテナ。
@MainActor
enum AppModelContainer {
    static let model = AppModel()
}

/// メニューバー右クリックメニューとそのインストール状態。
/// MenuBarExtra(.window) とキャラクターアニメーションは維持したまま、
/// 右クリック時のみ NSMenu を出す最小限のAppKitブリッジ（NSStatusItem移行はしない）。
@MainActor
enum MenuBarSupport {
    static let rightClickMonitor = MenuBarRightClickMonitor()
    static private(set) var contextMenuCoordinator: MenuBarContextMenuCoordinator?

    static func install(model: AppModel) {
        guard contextMenuCoordinator == nil else { return }
        let coordinator = MenuBarContextMenuCoordinator { action in
            model.handleMenuBarContextAction(action)
        }
        contextMenuCoordinator = coordinator

        rightClickMonitor.install { [weak coordinator] in
            guard let coordinator else { return false }
            let state = model.menuBarContextState
            let descriptor = MenuBarContextMenuBuilder.descriptor(
                accounts: state.accounts,
                selectedAccountID: state.selectedAccountID,
                isRefreshing: state.isRefreshing
            )
            let menu = coordinator.makeMenu(from: descriptor)
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return true
        }
    }
}

/// エントリポイント。MenuBarExtra のみで構成し Dock には表示しない
/// （.app バンドルの Info.plist で LSUIElement = 1 を設定する）。
/// 設定・初回セットアップ・クイック利用状況の各ウィンドウは
/// AppModel の AppWindowPresenter（NSWindow）から呈示する。
@main
struct AIUsageBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModelContainer.model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarCharacterLabel(
                state: model.characterState,
                motionPolicy: MotionPolicy.resolve(reduceMotionEnabled: reduceMotion)
            )
        }
        .menuBarExtraStyle(.window)
    }
}

/// LSUIElement アプリのためのアプリケーションデリゲート。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 起動時に即時取得と自動更新ループを開始する
        Task { @MainActor in
            let model = AppModelContainer.model
            model.start()
            MenuBarSupport.install(model: model)
            // 新規インストールでのみ初回セットアップを表示する
            if model.onboardingPending {
                model.startOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            AppModelContainer.model.stop()
        }
    }
}
