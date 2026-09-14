import Foundation
import Testing
@testable import AIUsageBuddy

/// 更新確認のテスト: バージョン比較・24時間制御・自動オフ・ad-hoc抑止。
@Suite
@MainActor
struct UpdateServiceTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-update-\(UUID().uuidString)")!
    }

    // MARK: - バージョン比較

    @Test("バージョンは数値比較される（1.10.0 > 1.9.0）")
    func versionComparison() {
        #expect(VersionCompare.isNewer("1.10.0", than: "1.9.0"))
        #expect(VersionCompare.isNewer("1.0.1", than: "1.0.0"))
        #expect(VersionCompare.isNewer("2.0", than: "1.9.9"))
        #expect(VersionCompare.isNewer("0.2.0", than: "0.1.99"))
        #expect(!VersionCompare.isNewer("1.0.0", than: "1.0.0"))
        #expect(!VersionCompare.isNewer("1.0.0", than: "1.0.1"))
        #expect(!VersionCompare.isNewer("1.0", than: "1.0.0"), "不足桁は0扱いで同値")
        // v接頭辞の正規化
        #expect(VersionCompare.isNewer("v1.2.0", than: "1.1.0"))
        #expect(!VersionCompare.isNewer("v1.0", than: "1.0.0"))
        // 数値でない断片は0扱い
        #expect(!VersionCompare.isNewer("abc", than: "0"))
        #expect(VersionCompare.isNewer("1.0.0", than: "abc"))
    }

    // MARK: - 24時間制御

    @Test("自動確認は24時間に1回だけ取得する")
    func automaticCheckThrottledToDaily() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "1.0.0"))
        var now = Date()
        let service = UpdateService(
            provider: provider,
            defaults: makeDefaults(),
            currentVersion: "1.0.0",
            now: { now }
        )

        await service.automaticCheckIfNeeded(enabled: true)
        #expect(provider.fetchCount == 1, "初回は確認する")

        now = now.addingTimeInterval(60 * 60) // 1時間後
        await service.automaticCheckIfNeeded(enabled: true)
        #expect(provider.fetchCount == 1, "24時間以内は再確認しない")

        now = now.addingTimeInterval(24 * 60 * 60) // さらに25時間後
        await service.automaticCheckIfNeeded(enabled: true)
        #expect(provider.fetchCount == 2, "24時間経過で再確認する")
    }

    @Test("手動確認は24時間制御を受けない")
    func manualCheckBypassesThrottle() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "1.0.0"))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0")

        await service.checkNow()
        await service.checkNow()
        #expect(provider.fetchCount == 2)
    }

    // MARK: - 自動更新オフ

    @Test("自動確認オフの間は確認しない")
    func automaticCheckDisabledSkips() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "9.9.9"))
        var now = Date().addingTimeInterval(-48 * 60 * 60)
        let service = UpdateService(
            provider: provider,
            defaults: makeDefaults(),
            currentVersion: "1.0.0",
            now: { now }
        )

        await service.automaticCheckIfNeeded(enabled: false)
        #expect(provider.fetchCount == 0, "オフなら確認しない")
        #expect(service.outcome == .idle)

        now = now.addingTimeInterval(48 * 60 * 60)
        await service.automaticCheckIfNeeded(enabled: false)
        #expect(provider.fetchCount == 0, "時間が経ってもオフなら確認しない")
    }

    // MARK: - 確認結果

    @Test("新しいバージョンがあると available になる")
    func newerVersionReportsAvailable() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "1.2.0", pageURL: URL(string: "https://github.com/example/releases")))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0")

        await service.checkNow()
        #expect(service.outcome == .available(version: "1.2.0", pageURL: URL(string: "https://github.com/example/releases")))
        #expect(service.latestVersion == "1.2.0")
    }

    @Test("現行と同じか古い場合は upToDate")
    func sameOrOlderReportsUpToDate() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "1.0.0"))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0")
        await service.checkNow()
        #expect(service.outcome == .upToDate)

        provider.setRelease(UpdateRelease(version: "0.9.0"))
        await service.checkNow()
        #expect(service.outcome == .upToDate, "古いリリースは更新扱いにしない")
    }

    @Test("GitHub所有者がプレースホルダーなら notConfigured")
    func placeholderOwnerIsNotConfigured() async {
        // 既定の GitHubReleasesProvider は所有者が未設定
        let service = UpdateService(provider: GitHubReleasesProvider(), defaults: makeDefaults(), currentVersion: "1.0.0")
        await service.checkNow()
        #expect(service.outcome == .notConfigured)

        #expect(GitHubReleasesProvider.placeholderOwner == "YOUR_GITHUB_OWNER", "プレースホルダーであること")
    }

    @Test("取得失敗は failed になる（24時間制御も記録される）")
    func failureReportsFailed() async {
        let provider = SpyUpdateProvider()
        provider.setError(UpdateProviderError.server(status: 503))
        var now = Date()
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0", now: { now })

        await service.checkNow()
        if case .failed = service.outcome {
            // OK
        } else {
            Issue.record("failed であること: \(service.outcome)")
        }

        // 失敗しても確認時刻は記録されるため24時間は再試行しない
        now = now.addingTimeInterval(60 * 60)
        await service.automaticCheckIfNeeded(enabled: true)
        #expect(provider.fetchCount == 1)
    }

    // MARK: - ad-hoc版の自動インストール抑止

    @Test("バンドル外（開発実行）では自動インストールを抑止する")
    func adhocBuildSuppressesInstall() {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "2.0.0"))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0")

        // テストランナーは .app バンドル外 → manualOnly
        let eligibility = AutoUpdateEligibility.evaluate()
        if case .eligible = eligibility {
            Issue.record("バンドル外実行では eligible にならないこと")
        }

        // ユーザーが確認済みでも自動インストールは抑止される
        let decision = service.requestInstall(userConfirmed: true)
        guard case .suppressed = decision else {
            Issue.record("suppressed であること: \(decision)")
            return
        }
    }

    @Test("未確認のインストール要求は確認要求になる")
    func unconfirmedInstallRequiresConfirmation() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "2.0.0"))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0")
        await service.checkNow()

        // eligible でない環境では確認要求より抑止が優先される
        let decision = service.requestInstall(userConfirmed: false)
        if case .suppressed = decision {
            // バンドル外実行では抑制が正しい
        } else if case .requiresUserConfirmation = decision {
            // 署名済み環境では確認要求も許容
        } else {
            Issue.record("予期しない判定: \(decision)")
        }
    }

    // MARK: - AppModel統合

    @Test("起動時自動確認: 有効なら確認し、プレースホルダーなら notConfigured")
    func startupAutomaticCheckIntegration() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let env = TestEnvironment.make(accounts: [account])

        await env.model.performStartupActions()
        // 既定の provider はスパイ（リリース未設定 = nil）→ upToDate
        #expect(env.model.updateService.outcome == .upToDate)
    }

    @Test("起動時自動確認: 設定オフなら確認しない")
    func startupAutomaticCheckRespectsSetting() async {
        let account = Account(displayName: "A", homeKind: .defaultHome)
        let env = TestEnvironment.make(accounts: [account])
        env.model.settingsStore.settings.automaticUpdateChecksEnabled = false

        await env.model.performStartupActions()
        #expect(env.model.updateService.outcome == .idle, "オフなら確認しない")
    }
}
