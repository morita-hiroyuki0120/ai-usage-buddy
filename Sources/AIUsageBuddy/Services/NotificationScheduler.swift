import Foundation
import UserNotifications
import AppKit

/// 通知送信の抽象（テストでスパイに差し替えられるようにする）。
@MainActor
public protocol NotificationScheduling: AnyObject {
    var authorizationStatus: UNAuthorizationStatus { get }
    func refreshAuthorizationStatus() async
    func requestAuthorization() async -> Bool
    func sendLowUsageNotification(_ decision: NotificationPolicy.Decision, language: AppLanguage) async
    func openSystemNotificationSettings()
}

/// UNUserNotificationCenter のラッパ。通知の送信と権限状態の管理を行う。
/// 通知音は初期オフ（音を設定しない）。
@MainActor
public final class NotificationScheduler: ObservableObject, NotificationScheduling {

    public static let shared = NotificationScheduler()

    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let logger = AppLogger(category: "NotificationScheduler")

    /// UNUserNotificationCenter は .app バンドル外（素のバイナリ実行等）では
    /// 生成時に例外でクラッシュするため、初期化時には触らず使用時のみ生成する。
    private var cachedCenter: UNUserNotificationCenter?
    private var center: UNUserNotificationCenter {
        if let cachedCenter { return cachedCenter }
        let center = UNUserNotificationCenter.current()
        cachedCenter = center
        return center
    }

    public init() {}

    public func refreshAuthorizationStatus() {
        Task {
            let settings = await center.notificationSettings()
            self.authorizationStatus = settings.authorizationStatus
        }
    }

    /// 通知権限を要求する。拒否された場合は設定画面への誘導が必要になる。
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge])
            refreshAuthorizationStatus()
            return granted
        } catch {
            logger.error("notification authorization failed: \(error.localizedDescription)")
            refreshAuthorizationStatus()
            return false
        }
    }

    /// 低残量通知を送信する。アカウント名と対象リミットを本文に含める。
    public func sendLowUsageNotification(_ decision: NotificationPolicy.Decision, language: AppLanguage) async {
        let content = UNMutableNotificationContent()
        let limitName = limitDisplayName(decision.kind, language: language)
        switch language {
        case .japanese:
            content.title = "AI Usage Buddy"
            content.body = "【\(decision.accountDisplayName)】\(limitName) 残り \(decision.remainingPercent)%（しきい値 \(decision.threshold)%）"
        case .english:
            content.title = "AI Usage Buddy"
            content.body = "[\(decision.accountDisplayName)] \(limitName): \(decision.remainingPercent)% remaining (threshold \(decision.threshold)%)"
        }
        // 通知音は初期オフ: sound を設定しない
        let request = UNNotificationRequest(
            identifier: decision.key,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            logger.error("failed to post notification: \(error.localizedDescription)")
        }
    }

    private func limitDisplayName(_ kind: QuotaLimitKind, language: AppLanguage) -> String {
        let key = kind.localizedNameKey
        switch language {
        case .japanese:
            return ["limit.fiveHour": "5時間枠", "limit.weekly": "週間枠"][key] ?? key
        case .english:
            return ["limit.fiveHour": "5-hour limit", "limit.weekly": "Weekly limit"][key] ?? key
        }
    }

    /// 通知権限が拒否されている場合にシステム設定を開く。
    public func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
