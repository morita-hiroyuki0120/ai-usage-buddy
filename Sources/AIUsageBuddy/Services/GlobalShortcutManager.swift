import Foundation
import Combine
import Carbon.HIToolbox
import AppKit

// MARK: - Validation

/// ショートカット設定の問題。
public enum ShortcutValidationIssue: Equatable, Sendable {
    /// 2つのショートカットが同じキー＋修飾キー（競合）。
    case duplicateSpecs
    /// 有効なのにキーが未指定。
    case missingKey
    /// 有効なのに修飾キーが未指定（素のキー入力を横取りするのを防ぐ）。
    case missingModifiers

    public var messageKey: String {
        switch self {
        case .duplicateSpecs: return "shortcut.error.duplicate"
        case .missingKey: return "shortcut.error.missingKey"
        case .missingModifiers: return "shortcut.error.missingModifiers"
        }
    }
}

/// ショートカット設定の検証（純粋関数）。
public enum ShortcutValidator {
    public static func issues(show: HotKeySpec, refresh: HotKeySpec) -> [ShortcutValidationIssue] {
        var issues: [ShortcutValidationIssue] = []
        for spec in [show, refresh] where spec.enabled {
            if spec.keyCode < 0 { issues.append(.missingKey) }
            if spec.modifiers == 0 { issues.append(.missingModifiers) }
        }
        if show.enabled, refresh.enabled, show.matches(keyCode: refresh.keyCode, modifiers: refresh.modifiers) {
            issues.append(.duplicateSpecs)
        }
        return issues
    }
}

// MARK: - Registration abstraction

/// ホットキー登録の抽象（テストではスパイに差し替える）。
public protocol HotKeyRegistering: AnyObject, Sendable {
    /// 登録に成功したかを返す。
    @discardableResult
    func register(id: UInt32, keyCode: Int, modifiers: Int) -> Bool
    func unregister(id: UInt32)
}

/// Carbon のホットキーコールバック格納庫。
/// Carbon のイベントハンドラはC関数ポインタで呼ばれるため、ここを経由して
/// MainActor へ配送する（コールバック内でSwiftUIを直接操作しない）。
enum HotKeyCallbackStore {
    static var callbacks: [UInt32: () -> Void] = [:]

    static func dispatch(id: UInt32) {
        guard let callback = callbacks[id] else { return }
        Task { @MainActor in
            callback()
        }
    }
}

/// Carbon (RegisterEventHotKey) による実際の登録実装。
/// 状態は NSLock で保護しているため @unchecked Sendable。
public final class CarbonHotKeyRegistrar: HotKeyRegistering, @unchecked Sendable {

    /// EventHotKeyID の署名（"AUB1"）。
    private static let signature: OSType = 0x41_55_42_31

    private let lock = NSLock()
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    public init() {}

    @discardableResult
    public func register(id: UInt32, keyCode: Int, modifiers: Int) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        lock.lock()
        hotKeyRefs[id] = ref
        lock.unlock()
        return true
    }

    public func unregister(id: UInt32) {
        lock.lock()
        let ref = hotKeyRefs.removeValue(forKey: id)
        lock.unlock()
        if let ref {
            UnregisterEventHotKey(ref)
        }
    }

    /// kEventHotKeyPressed を1度だけアプリのイベントターゲットへ登録する。
    private func installHandlerIfNeeded() {
        lock.lock()
        let installed = handlerInstalled
        handlerInstalled = true
        lock.unlock()
        guard !installed else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    HotKeyCallbackStore.dispatch(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}

// MARK: - Manager

/// グローバルショートカットの適用・状態管理。
/// 検証失敗・登録失敗は @Published で設定UIへ表示する。
@MainActor
public final class GlobalShortcutManager: ObservableObject {

    public static let showUsageHotKeyID: UInt32 = 1
    public static let refreshHotKeyID: UInt32 = 2

    @Published public private(set) var validationIssues: [ShortcutValidationIssue] = []
    @Published public private(set) var failedShortcutNames: [String] = []

    /// ⌃⌥U などが押されたとき（クイック利用状況ウインドウのトグル）。
    public var onShowUsage: (() -> Void)?
    /// ⌃⌥R などが押されたとき（手動更新）。
    public var onRefresh: (() -> Void)?

    private let registrar: HotKeyRegistering

    public init(registrar: HotKeyRegistering = CarbonHotKeyRegistrar()) {
        self.registrar = registrar
    }

    /// 設定を検証して反映する。検証に問題がある場合はすべて解除する。
    public func apply(show: HotKeySpec, refresh: HotKeySpec) {
        let issues = ShortcutValidator.issues(show: show, refresh: refresh)
        validationIssues = issues
        guard issues.isEmpty else {
            unregisterAll()
            return
        }

        var failures: [String] = []
        if show.enabled {
            HotKeyCallbackStore.callbacks[Self.showUsageHotKeyID] = { [weak self] in
                self?.onShowUsage?()
            }
            if !registrar.register(id: Self.showUsageHotKeyID, keyCode: show.keyCode, modifiers: show.modifiers) {
                failures.append("shortcut.name.showUsage")
            }
        } else {
            registrar.unregister(id: Self.showUsageHotKeyID)
        }
        if refresh.enabled {
            HotKeyCallbackStore.callbacks[Self.refreshHotKeyID] = { [weak self] in
                self?.onRefresh?()
            }
            if !registrar.register(id: Self.refreshHotKeyID, keyCode: refresh.keyCode, modifiers: refresh.modifiers) {
                failures.append("shortcut.name.refresh")
            }
        } else {
            registrar.unregister(id: Self.refreshHotKeyID)
        }
        failedShortcutNames = failures
    }

    /// すべてのホットキーを解除する（アプリ終了時・検証失敗時）。
    public func unregisterAll() {
        registrar.unregister(id: Self.showUsageHotKeyID)
        registrar.unregister(id: Self.refreshHotKeyID)
        HotKeyCallbackStore.callbacks[Self.showUsageHotKeyID] = nil
        HotKeyCallbackStore.callbacks[Self.refreshHotKeyID] = nil
        failedShortcutNames = []
    }

    /// NSEvent の修飾キーから Carbon の修飾キーフラグへ変換（キー記録UIで使用）。
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.control) { carbon |= CarbonModifier.control }
        if flags.contains(.option) { carbon |= CarbonModifier.option }
        if flags.contains(.shift) { carbon |= CarbonModifier.shift }
        if flags.contains(.command) { carbon |= CarbonModifier.cmd }
        return carbon
    }
}
