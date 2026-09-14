import Foundation
import Combine
import AppKit
import SwiftUI

/// 呈示する補助ウィンドウの種類。
public enum AppWindowKind: String, Equatable, Sendable {
    case settings
    case onboarding
    case quickUsage
}

/// ウィンドウ呈示の抽象（テストではスパイに差し替える）。
@MainActor
public protocol AppWindowHosting: AnyObject {
    @discardableResult
    func show(kind: AppWindowKind, titleKey: String?, content: AnyView, size: NSSize) -> Bool
    func close(kind: AppWindowKind)
    func isVisible(kind: AppWindowKind) -> Bool
}

/// 設定・初回セットアップ・クイック利用状況のウィンドウを管理する。
/// MenuBarExtra は SwiftUI Scene のまま維持し、ここではそれ以外の補助ウィンドウのみ扱う。
@MainActor
public final class AppWindowPresenter: ObservableObject {

    private let host: AppWindowHosting

    public init(host: AppWindowHosting? = nil) {
        self.host = host ?? AppWindowHost()
    }

    // MARK: - Settings

    public func showSettings(content: @autoclosure @escaping () -> AnyView) {
        _ = host.show(
            kind: .settings,
            titleKey: "settings.title",
            content: content(),
            size: NSSize(width: 580, height: 700)
        )
    }

    // MARK: - Onboarding

    public func showOnboarding(content: @autoclosure @escaping () -> AnyView) {
        _ = host.show(
            kind: .onboarding,
            titleKey: "onboarding.window.title",
            content: content(),
            size: NSSize(width: 520, height: 460)
        )
    }

    public func closeOnboarding() {
        host.close(kind: .onboarding)
    }

    // MARK: - Quick usage

    /// クイック利用状況ウインドウの表示／非表示を切り替える。
    /// 内容はポップオーバーと同じ PopoverView（表示ロジックの共有）。
    public func toggleQuickUsage(content: @autoclosure @escaping () -> AnyView) {
        if host.isVisible(kind: .quickUsage) {
            host.close(kind: .quickUsage)
        } else {
            _ = host.show(
                kind: .quickUsage,
                titleKey: "quickusage.window.title",
                content: content(),
                size: NSSize(width: 348, height: 540)
            )
        }
    }

    public func closeQuickUsage() {
        host.close(kind: .quickUsage)
    }

    public func isVisible(kind: AppWindowKind) -> Bool {
        host.isVisible(kind: kind)
    }
}

/// NSWindow + NSHostingView による実際のウィンドウ実装。
@MainActor
public final class AppWindowHost: AppWindowHosting {

    private var windows: [AppWindowKind: NSWindow] = [:]

    public init() {}

    @discardableResult
    public func show(kind: AppWindowKind, titleKey: String?, content: AnyView, size: NSSize) -> Bool {
        let window: NSWindow
        if let existing = windows[kind] {
            window = existing
            window.contentView = NSHostingView(rootView: content)
        } else {
            var styleMask: NSWindow.StyleMask = [.titled, .miniaturizable]
            if kind != .onboarding {
                // 初回セットアップは明示的なスキップ／完了ボタンで閉じる設計のため
                // 閉じるボタンを付けない（スキップ可能であることはUIで保証する）
                styleMask.insert(.closable)
            }
            if kind == .settings {
                styleMask.insert(.resizable)
            }
            let newWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            newWindow.title = titleKey.map { L($0) } ?? ""
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = NSHostingView(rootView: content)
            newWindow.center()
            windows[kind] = newWindow
            window = newWindow
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    public func close(kind: AppWindowKind) {
        if let window = windows[kind] {
            window.orderOut(nil)
        }
    }

    public func isVisible(kind: AppWindowKind) -> Bool {
        windows[kind]?.isVisible ?? false
    }
}

/// テスト用のスパイホスト。呼び出しを記録するだけでウィンドウを作らない。
@MainActor
public final class SpyWindowHost: AppWindowHosting {
    public struct Call: Equatable, Sendable {
        public let kind: AppWindowKind
        public let titleKey: String?
        public let contentDescription: String
    }

    public private(set) var showCalls: [Call] = []
    public private(set) var closeCalls: [AppWindowKind] = []
    /// 表示中とみなす種類（テストが制御する）。
    public var visibleKinds: Set<AppWindowKind> = []

    public init() {}

    @discardableResult
    public func show(kind: AppWindowKind, titleKey: String?, content: AnyView, size: NSSize) -> Bool {
        showCalls.append(Call(kind: kind, titleKey: titleKey, contentDescription: String(describing: content)))
        visibleKinds.insert(kind)
        return true
    }

    public func close(kind: AppWindowKind) {
        closeCalls.append(kind)
        visibleKinds.remove(kind)
    }

    public func isVisible(kind: AppWindowKind) -> Bool {
        visibleKinds.contains(kind)
    }
}
