import Foundation
import Testing
import SwiftUI
@testable import AIUsageBuddy

/// 言語切り替え・ライト/ダーク・Reduce Motion・ログ検閲のテスト。
@Suite
struct LocalizationAndAccessibilityTests {

    // MARK: - 日本語／英語切り替え

    @Test("日本語と英語で文字列が切り替わる")
    func japaneseAndEnglishStringsDiffer() {
        let manager = LocalizationManager(defaults: isolatedDefaults())

        manager.override = .japanese
        let ja = manager.string(key: "limit.fiveHour", language: .japanese)
        #expect(ja == "5時間枠")

        let en = manager.string(key: "limit.fiveHour", language: .english)
        #expect(en == "5-hour limit")
        #expect(ja != en)
    }

    @Test("言語の手動上書きは永続化される")
    func languageOverrideRoundTrip() {
        let defaults = isolatedDefaults()
        let manager = LocalizationManager(defaults: defaults)

        manager.override = .english
        #expect(defaults.string(forKey: "com.aiusagebuddy.app.languageOverride") == "en")

        manager.resetToSystemLanguage()
        #expect(defaults.string(forKey: "com.aiusagebuddy.app.languageOverride") == nil)
    }

    @Test("主要キーは両言語とも翻訳が存在する")
    func keySetExistsForBothLanguages() {
        let manager = LocalizationManager(defaults: isolatedDefaults())
        let keys = [
            "app.name",
            "limit.fiveHour",
            "limit.weekly",
            "character.state.energetic",
            "character.state.normal",
            "character.state.tired",
            "character.state.sleeping",
            "character.state.unknown",
            "popover.account",
            "popover.noData",
            "popover.resetUnknown",
            "popover.manualBadge",
            "popover.staleWarning",
            "popover.lastFetched",
            "popover.refresh.help",
            "popover.openSettings",
            "popover.quit",
            "settings.accounts",
            "settings.addAccount",
            "settings.notificationsEnabled",
            "settings.launchAtLogin",
            "settings.language",
            "settings.manual.apply",
        ]
        for key in keys {
            for language in AppLanguage.allCases {
                let value = manager.string(key: key, language: language)
                #expect(value != key, "\(language.rawValue) にキー \(key) の翻訳が無い")
            }
        }
    }

    @Test("存在しないキーはキーそのものにフォールバック")
    func fallbackToKeyWhenMissing() {
        let manager = LocalizationManager(defaults: isolatedDefaults())
        #expect(manager.string(key: "nonexistent.key", language: .japanese) == "nonexistent.key")
    }

    // MARK: - ライト／ダークモード

    @Test("パレットはカラースキームと高コントラストに追従する")
    func paletteAdaptsToColorScheme() {
        let lightNormal = CharacterPalette.bodyOpacity(for: .light, highContrast: false)
        let darkNormal = CharacterPalette.bodyOpacity(for: .dark, highContrast: false)
        #expect(lightNormal > 0)
        #expect(darkNormal > 0)

        #expect(CharacterPalette.bodyOpacity(for: .light, highContrast: true) == 1.0)
        #expect(CharacterPalette.bodyOpacity(for: .dark, highContrast: true) == 1.0)
    }

    // MARK: - Reduce Motion

    @Test("Reduce Motion 有効時はアニメーション無効")
    func reduceMotionDisablesAnimation() {
        #expect(MotionPolicy.resolve(reduceMotionEnabled: true) == .staticOnly)
        #expect(MotionPolicy.resolve(reduceMotionEnabled: false) == .animated)
    }

    // MARK: - 認証情報がログへ出ないこと

    @Test("メールアドレスはログから除去される")
    func logRedactorRemovesEmails() {
        let input = "account user@example.com logged in"
        let scrubbed = LogRedactor.scrub(input)
        #expect(!scrubbed.contains("user@example.com"))
        #expect(scrubbed.contains("[redacted]"))
    }

    @Test("トークン類はログから除去される")
    func logRedactorRemovesTokens() {
        let cases = [
            "Bearer eyJhbGciOiJIUzI1NiJ9(payload(signature",
            "access_token=abc123def456ghi789jkl012mno345",
            "refresh_token: zzz999yyy888xxx777www666vvv555uuu444",
        ]
        for input in cases {
            let scrubbed = LogRedactor.scrub(input)
            #expect(
                !(scrubbed.contains("eyJhbGci") || scrubbed.contains("abc123def456") || scrubbed.contains("zzz999yyy888")),
                "トークンが除去されていること: \(scrubbed)"
            )
        }
    }

    @Test("クライアント実装は auth.json を直接参照しない")
    func clientNeverLogsAuthFileContents() {
        // auth.json を読まない設計であることをソースレベルで保証する
        let sources = [
            "Sources/AIUsageBuddy/Services/CodexAppServerClient.swift",
            "Sources/AIUsageBuddy/Services/CodexUsageProvider.swift",
        ]
        for path in sources {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                Issue.record("ソースが読めない: \(path)")
                continue
            }
            #expect(!text.contains("auth.json"), "\(path) は auth.json を直接参照してはいけない")
        }
    }

    // MARK: - Helpers

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-loc-\(UUID().uuidString)")!
    }
}
