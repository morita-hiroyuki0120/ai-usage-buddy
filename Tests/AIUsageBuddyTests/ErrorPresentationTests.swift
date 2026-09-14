import Foundation
import Testing
@testable import AIUsageBuddy

/// エラー分類・stale表示・失敗時の通知抑制・詳細情報の秘密情報除去のテスト。
@Suite
@MainActor
struct ErrorPresentationTests {

    /// メールアドレス等を含むエラー（検閲対象）。
    private struct SensitiveError: LocalizedError {
        var errorDescription: String? {
            "login failed for user@example.com via https://auth.example.com/login?code=aS3cr3tTok3nValue000000000000"
        }
    }

    private func makeSnapshot(accountID: UUID, fiveHourRemaining: Int) -> UsageSnapshot {
        UsageSnapshot(
            accountID: accountID,
            fiveHour: QuotaWindow(
                kind: .fiveHour,
                remainingPercent: fiveHourRemaining,
                resetAt: Date().addingTimeInterval(3600),
                fetchedAt: Date(),
                state: .fresh
            ),
            weekly: QuotaWindow(
                kind: .weekly,
                remainingPercent: 50,
                resetAt: Date().addingTimeInterval(86400),
                fetchedAt: Date(),
                state: .fresh
            ),
            fetchedAt: Date()
        )
    }

    // MARK: - エラー分類

    @Test("CodexClientErrorを種別に分類する")
    func classificationOfClientErrors() {
        #expect(UsageErrorKind.classify(CodexClientError.authenticationRequired) == .authenticationRequired)
        #expect(UsageErrorKind.classify(CodexClientError.binaryNotFound(path: "/x")) == .officialIntegrationMissing)
        #expect(UsageErrorKind.classify(CodexClientError.launchFailed("x")) == .officialIntegrationMissing)
        #expect(UsageErrorKind.classify(CodexClientError.timeout(method: "account/rateLimits/read")) == .timeout)
        #expect(UsageErrorKind.classify(CodexClientError.serverError(code: -32000, message: "boom")) == .serverError)
        #expect(UsageErrorKind.classify(CodexClientError.invalidResponse("bad")) == .invalidResponse)
        #expect(UsageErrorKind.classify(CodexClientError.terminated) == .processTerminated)
        #expect(UsageErrorKind.classify(NSError(domain: "test", code: 1)) == .other)
    }

    @Test("種別ごとに説明と導線が定義されている")
    func everyKindHasExplanationAndAction() {
        for kind in UsageErrorKind.allCases {
            #expect(kind.recommendedAction == .retry || kind.recommendedAction == .openSettings)
        }
        #expect(UsageErrorKind.authenticationRequired.recommendedAction == .openSettings, "認証が必要は設定導線")
        #expect(UsageErrorKind.timeout.recommendedAction == .retry, "タイムアウトは再試行")
    }

    @Test("エラー種別の文言は日英ともに定義されている")
    func errorKindLocalization() {
        let manager = LocalizationManager(defaults: UserDefaults(suiteName: "test-loc-\(UUID().uuidString)")!)
        for kind in UsageErrorKind.allCases {
            for language in AppLanguage.allCases {
                #expect(manager.string(key: kind.titleKey, language: language) != kind.titleKey, "\(language.rawValue): \(kind.titleKey)")
                #expect(manager.string(key: kind.explanationKey, language: language) != kind.explanationKey, "\(language.rawValue): \(kind.explanationKey)")
            }
        }
        for action in ErrorAction.allCases {
            for language in AppLanguage.allCases {
                #expect(manager.string(key: action.buttonTitleKey, language: language) != action.buttonTitleKey)
            }
        }
    }

    // MARK: - stale表示（前回値保持）

    @Test("取得失敗時は種別を記録し前回値・表示残量を保持する")
    func fetchFailureKeepsValuesAndRecordsKind() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 40)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])

        await env.model.refreshAll(sendNotifications: false) // 前回値を確定
        #expect(env.model.displayedPercent == 40)

        env.provider.setFetchError(CodexClientError.timeout(method: "account/rateLimits/read"))
        await env.model.refreshAll(sendNotifications: false)

        let snapshot = env.model.snapshots[account.id]
        #expect(snapshot?.lastErrorKind == .timeout, "種別が記録される")
        #expect(snapshot?.fiveHour?.remainingPercent == 40, "残量は前回値")
        #expect(snapshot?.fiveHour?.state == .stale, "stale表示")
        #expect(env.model.displayedPercent == 40, "表示残量も前回値を保持")
    }

    @Test("成功するとエラー状態はクリアされる")
    func successClearsErrorState() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 40)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])

        // まず成功させて前回値をストアへ入れる
        await env.model.refreshAll(sendNotifications: false)
        // 失敗させる
        env.provider.setFetchError(CodexClientError.terminated)
        await env.model.refreshAll(sendNotifications: false)
        #expect(env.model.snapshots[account.id]?.lastErrorKind != nil)

        // 再び成功するとエラー状態は消える
        env.provider.setFetchError(nil)
        await env.model.refreshAll(sendNotifications: false)
        #expect(env.model.snapshots[account.id]?.lastErrorKind == nil)
        #expect(env.model.snapshots[account.id]?.lastErrorMessage == nil)
        #expect(env.model.snapshots[account.id]?.fiveHour?.state == .fresh)
    }

    // MARK: - 失敗時の通知抑制

    @Test("取得に失敗したアカウントからは低残量通知を送らない")
    func noLowUsageNotificationAfterFetchFailure() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        // 低残量（5%）の前回値がある状態で取得に失敗する
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 5)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])
        await env.model.refreshAll(sendNotifications: false)
        #expect(env.spy.sentNotifications.isEmpty, "sendNotifications: false の初期取得では通知しない")

        env.provider.setFetchError(CodexClientError.serverError(code: -32000, message: "unavailable"))
        await env.model.refreshAll(sendNotifications: true)

        #expect(env.spy.sentNotifications.isEmpty, "取得失敗中は前回値が低残量でも通知しない")
    }

    @Test("取得に成功している低残量からは通知する（対照）")
    func lowUsageNotifiesWhenFetchSucceeds() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 5)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])

        await env.model.refreshAll(sendNotifications: true)

        #expect(!env.spy.sentNotifications.isEmpty, "成功時は低残量通知が出る")
    }

    // MARK: - 詳細情報の秘密情報除去

    @Test("エラー詳細は認証情報・秘密URLを除去して保存される")
    func errorDetailIsScrubbedBeforeStorage() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let initial = makeSnapshot(accountID: account.id, fiveHourRemaining: 40)
        let env = TestEnvironment.make(accounts: [account], snapshots: [initial])
        await env.model.refreshAll(sendNotifications: false)

        env.provider.setFetchError(SensitiveError())
        await env.model.refreshAll(sendNotifications: false)

        let detail = env.model.snapshots[account.id]?.lastErrorMessage ?? ""
        #expect(!detail.contains("user@example.com"), "メールアドレスは含まれない")
        #expect(!detail.contains("aS3cr3tTok3nValue"), "URL内トークンは含まれない")
        #expect(detail.contains("[redacted"), "検閲済みである")

        // 永続化されたファイルにも秘密情報が無い
        if let data = try? Data(contentsOf: env.container.appendingPathComponent("snapshots.json")),
           let text = String(data: data, encoding: .utf8) {
            #expect(!text.contains("user@example.com"))
            #expect(!text.contains("aS3cr3tTok3nValue"))
        } else {
            Issue.record("snapshots.json が読めること")
        }
    }

    @Test("LogRedactorはクエリ付きURLを除去する")
    func logRedactorScrubsSecretURLs() {
        let input = "open https://auth.example.com/login?code=SECRET123456789012345 to continue"
        let scrubbed = LogRedactor.scrub(input)
        #expect(!scrubbed.contains("SECRET123456789012345"))
        #expect(scrubbed.contains("[redacted"))
        #expect(scrubbed.contains("open"), "URL以外の文言は保持")
    }

    @Test("OAuth認証URL形式（フラグメント付き）も除去される")
    func logRedactorScrubsFragmentURLs() {
        let input = "auth url: https://chatgpt.com/account/login#access_token=eyJabc.def.ghi&state=xyz123456789012345678901234567890"
        let scrubbed = LogRedactor.scrub(input)
        #expect(!scrubbed.contains("access_token=eyJabc"))
        #expect(!scrubbed.contains("https://chatgpt.com/account/login#"))
    }
}
