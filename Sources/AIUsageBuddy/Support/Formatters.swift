import Foundation

/// リセット日時・残り時間の表示整形（テスト可能な純粋ロジック）。
public enum UsageFormatter {

    /// リセットまでの残り時間を「3時間12分」形式の文字列にする。
    /// 残りが負の場合（リセット済み）は "0分" を返す。
    public static func remainingTime(from now: Date, to resetAt: Date, language: AppLanguage) -> String {
        let seconds = max(0, resetAt.timeIntervalSince(now))
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        switch language {
        case .japanese:
            if days > 0 {
                return "\(days)日 \(hours)時間 \(minutes)分"
            } else if hours > 0 {
                return "\(hours)時間 \(minutes)分"
            } else {
                return "\(minutes)分"
            }
        case .english:
            if days > 0 {
                return "\(days)d \(hours)h \(minutes)m"
            } else if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
    }

    /// リセット日時をローカルタイムゾーンで表示用に整形する。
    public static func resetDateTime(_ resetAt: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        formatter.locale = locale
        return formatter.string(from: resetAt)
    }

    /// 最終取得日時を表示用に整形する。
    public static func fetchedDateTime(_ fetchedAt: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        formatter.locale = locale
        return formatter.string(from: fetchedAt)
    }

    /// 残量％の表示文字列（ローカライズ済み）。
    public static func percent(_ value: Int, language: AppLanguage) -> String {
        switch language {
        case .japanese: return "\(value)%"
        case .english: return "\(value)%"
        }
    }
}
