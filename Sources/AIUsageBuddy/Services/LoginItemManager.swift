import Foundation
import ServiceManagement

/// ログイン項目登録のエラー。
public struct LoginItemError: Error, LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// ログイン時自動起動の操作（テストでスパイに差し替え可能）。
/// 登録は必ずユーザーの明示操作（設定トグル・初回セットアップのボタン）からのみ行う。
public protocol LoginItemManaging: Sendable {
    /// 現在の登録状態。
    func isEnabled() -> Bool
    /// 登録／解除。失敗した場合はエラーを返す。
    func setEnabled(_ enabled: Bool) -> Result<Void, LoginItemError>
}

/// SMAppService を使った公式実装。
public struct SMAppServiceLoginItemManager: LoginItemManaging {

    public init() {}

    public func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) -> Result<Void, LoginItemError> {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return .success(()) }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return .success(()) }
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            return .failure(LoginItemError(message: error.localizedDescription))
        }
    }
}

/// 旧コードとの互換のための静的ラッパ（内部で SMAppServiceLoginItemManager を使う）。
public enum LoginItemManager {

    private static let implementation: LoginItemManaging = SMAppServiceLoginItemManager()

    /// 現在の登録状態。
    public static func isEnabled() -> Bool {
        implementation.isEnabled()
    }

    /// 登録（ログイン項目に追加）。失敗した場合はエラーを返す。
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Result<Void, LoginItemError> {
        implementation.setEnabled(enabled)
    }
}
