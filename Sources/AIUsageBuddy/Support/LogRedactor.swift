import Foundation
import os

/// ログに出力してはならない情報（メールアドレス・トークン類）を除去するフィルタ。
/// 認証情報がログへ出ないことをユニットテストで保証するために使用する。
public enum LogRedactor {

    /// 除去対象のパターンに一致する部分を "[redacted]" に置換する。
    public static func scrub(_ text: String) -> String {
        var result = text

        // メールアドレス
        result = replace(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, in: result)

        // Bearer / token 形式
        result = replace(pattern: #"(?i)(bearer\s+)[A-Za-z0-9._\-]+"#, in: result, keepPrefix: "$1")
        result = replace(pattern: #"(?i)((?:access[_\-]?token|refresh[_\-]?token|id[_\-]?token|api[_\-]?key|session[_\-]?key)["'\s:=]+)[A-Za-z0-9._\-]+"#, in: result, keepPrefix: "$1")

        // デバイスコード（userCode）
        result = replace(pattern: #"(?i)(user[_\-\s]?code["'\s:=]+)[A-Za-z0-9\-]+"#, in: result, keepPrefix: "$1")

        // JWT 形式（3分割のドット区切り）
        result = replace(pattern: #"[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}"#, in: result)

        // 長い連続英数字トークン（32文字以上）: 単語境界付き
        result = replace(pattern: #"\b[A-Za-z0-9_\-]{32,}\b"#, in: result)

        // 秘密URL: クエリ・フラグメント付きURL（OAuth認証URL等のトークン混入を防ぐ）
        result = replace(pattern: #"(?i)https?://[^\s\"'<>]+[?#][^\s\"'<>]+"#, in: result, replacement: "[redacted-url]")

        return result
    }

    private static func replace(pattern: String, in text: String, keepPrefix: String? = nil, replacement: String = "[redacted]") -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let template = keepPrefix.map { "\($0)[redacted]" } ?? replacement
        guard regex.firstMatch(in: text, range: range) != nil else { return text }
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

/// 認証情報を確実に除外してログ出力するロガー。
public struct AppLogger: Sendable {
    public let category: String
    private let logger: Logger

    public init(category: String) {
        self.category = category
        self.logger = Logger(subsystem: "com.aiusagebuddy.app", category: LogRedactor.scrub(category))
    }

    public func info(_ message: String) {
        logger.info("\(LogRedactor.scrub(message), privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(LogRedactor.scrub(message), privacy: .public)")
    }

    public func debug(_ message: String) {
        logger.debug("\(LogRedactor.scrub(message), privacy: .public)")
    }
}
