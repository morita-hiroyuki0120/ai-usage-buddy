import Foundation
import Testing
@testable import AIUsageBuddy

/// リリース設定と配布まわりのテスト: 未設定時の通信抑止・URL検証・署名資格・成果物命名・チェックサム。
/// URLProtocol の録画カウンタを共有するため直列実行する。
@Suite(.serialized)
@MainActor
struct ReleaseConfigurationTests {

    @Test("Store support uses only the approved public HTTPS destination")
    func storeSupportURLIsExactAndHasNoUserPayload() throws {
        let url = try #require(ReleaseConfiguration.storeSupportURL)
        #expect(url.absoluteString == "https://github.com/morita-hiroyuki0120/ai-usage-buddy/issues")
        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.path == "/morita-hiroyuki0120/ai-usage-buddy/issues")
        #expect(url.query == nil)
        #expect(url.fragment == nil)
        #expect(url.user == nil && url.password == nil && url.port == nil)
    }

    @Test("Store support label and browser hint exist in Japanese and English")
    func storeSupportStringsAreLocalized() {
        let name = "StoreSupportStrings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = LocalizationManager(defaults: defaults)
        for key in ["settings.about.support", "settings.about.supportHint"] {
            for language in AppLanguage.allCases {
                let value = manager.string(key: key, language: language)
                #expect(!value.isEmpty && value != key)
            }
        }
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-release-\(UUID().uuidString)")!
    }

    // MARK: - 通信抑止（未設定時にネットワークアクセスしない）

    /// すべてのロード要求を記録するだけのURLProtocol（实际には通信しない）。
    final class RecordingURLProtocol: URLProtocol {
        nonisolated(unsafe) static var loadCount = 0

        override class func canInit(with request: URLRequest) -> Bool {
            Self.loadCount += 1
            return false
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }
    }

    private func makeRecordingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("GitHub所有者が未設定（プレースホルダー）なら通信しない")
    func unconfiguredOwnerPerformsNoNetworkAccess() async {
        RecordingURLProtocol.loadCount = 0
        let provider = GitHubReleasesProvider(
            owner: GitHubReleasesProvider.placeholderOwner,
            urlSession: makeRecordingSession()
        )

        do {
            _ = try await provider.fetchLatestRelease()
            Issue.record("notConfigured が投げられること")
        } catch let error as UpdateProviderError {
            #expect(error == .notConfigured)
        } catch {
            Issue.record("予期しないエラー: \(error)")
        }
        #expect(RecordingURLProtocol.loadCount == 0, "ネットワーク要求が発生していないこと")
    }

    @Test("GitHub所有者が空文字でも通信しない")
    func emptyOwnerPerformsNoNetworkAccess() async {
        RecordingURLProtocol.loadCount = 0
        let provider = GitHubReleasesProvider(owner: "", urlSession: makeRecordingSession())

        do {
            _ = try await provider.fetchLatestRelease()
            Issue.record("notConfigured が投げられること")
        } catch let error as UpdateProviderError {
            #expect(error == .notConfigured)
        } catch {
            Issue.record("予期しないエラー: \(error)")
        }
        #expect(RecordingURLProtocol.loadCount == 0, "ネットワーク要求が発生していないこと")
    }

    // MARK: - ReleaseConfiguration の検証

    @Test("所有者の正規化: nil・空・プレースホルダーは未設定")
    func ownerNormalization() {
        #expect(ReleaseConfiguration.normalizeOwner(nil) == nil)
        #expect(ReleaseConfiguration.normalizeOwner("") == nil)
        #expect(ReleaseConfiguration.normalizeOwner("   ") == nil)
        #expect(ReleaseConfiguration.normalizeOwner(ReleaseConfiguration.placeholderOwnerValue) == nil)
        #expect(ReleaseConfiguration.normalizeOwner("your-account") == "your-account")
        #expect(ReleaseConfiguration.normalizeOwner("  your-account ") == "your-account")
    }

    @Test("Appcast URLはHTTPSのみ・プレースホルダー拒否")
    func appcastURLValidation() {
        // 未設定
        #expect(ReleaseConfiguration.validAppcastURL(nil) == nil)
        #expect(ReleaseConfiguration.validAppcastURL("") == nil)
        // HTTPS以外は拒否
        #expect(ReleaseConfiguration.validAppcastURL("http://example.com/appcast.xml") == nil)
        #expect(ReleaseConfiguration.validAppcastURL("ftp://example.com/appcast.xml") == nil)
        // プレースホルダーは拒否
        #expect(ReleaseConfiguration.validAppcastURL(ReleaseConfiguration.placeholderAppcastValue) == nil)
        // ホスト無し・不正URLは拒否
        #expect(ReleaseConfiguration.validAppcastURL("not-a-url") == nil)
        #expect(ReleaseConfiguration.validAppcastURL("https:///appcast.xml") == nil)
        // 有効なHTTPS URLのみ許可
        let valid = ReleaseConfiguration.validAppcastURL("https://example.github.io/appcast.xml")
        #expect(valid?.absoluteString == "https://example.github.io/appcast.xml")
    }

    @Test("テストランナー（Info.plistにGitHubOwner無し）では未設定として扱われる")
    func testRunnerBundleIsUnconfigured() {
        // swift test 実行時の Bundle.main には GitHubOwner が無い
        let configuration = ReleaseConfiguration.from(bundle: .main)
        #expect(configuration.githubOwner == nil)
        #expect(!configuration.isGitHubConfigured)
        #expect(configuration.effectiveGitHubOwner == GitHubReleasesProvider.placeholderOwner)
        #expect(configuration.releasesPageURL == nil, "未設定ならリリースページURLも作らない")
        #expect(configuration.githubRepository == GitHubReleasesProvider.defaultRepository)
    }

    @Test("未設定のeffectiveGitHubOwnerで組み立てたproviderは通信しない")
    func configurationBridgeProducesNonConfiguredProvider() async {
        let configuration = ReleaseConfiguration(
            githubOwner: nil,
            githubRepository: "AIUsageBuddy",
            appVersion: "1.0.0",
            buildNumber: "1"
        )
        let provider = GitHubReleasesProvider(
            configuration: configuration,
            urlSession: makeRecordingSession()
        )
        RecordingURLProtocol.loadCount = 0
        do {
            _ = try await provider.fetchLatestRelease()
            Issue.record("notConfigured が投げられること")
        } catch let error as UpdateProviderError {
            #expect(error == .notConfigured)
        } catch {
            Issue.record("予期しないエラー: \(error)")
        }
        #expect(RecordingURLProtocol.loadCount == 0)
    }

    @Test("設定済みの所有者ならリリースページURLを組み立てる")
    func configuredOwnerProducesReleasesURL() {
        let configuration = ReleaseConfiguration(
            githubOwner: "your-account",
            githubRepository: "AIUsageBuddy",
            appVersion: "1.0.0",
            buildNumber: "1"
        )
        #expect(configuration.isGitHubConfigured)
        #expect(configuration.effectiveGitHubOwner == "your-account")
        #expect(configuration.releasesPageURL?.absoluteString == "https://github.com/your-account/AIUsageBuddy/releases/latest")
    }

    // MARK: - 署名資格（自動インストールの可否）

    @Test("ad-hoc署名では自動インストールを抑止する")
    func adhocEligibilitySuppressesInstall() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "2.0.0"))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0", distributionChannel: .direct)
        await service.checkNow()

        let decision = service.requestInstall(
            userConfirmed: true,
            eligibility: .manualOnly(reason: .adhocSigned)
        )
        #expect(decision == .suppressed(reason: .adhocSigned))
    }

    @Test("未署名では自動インストールを抑止する")
    func unsignedEligibilitySuppressesInstall() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "2.0.0"))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0", distributionChannel: .direct)
        await service.checkNow()

        let decision = service.requestInstall(
            userConfirmed: true,
            eligibility: .manualOnly(reason: .unsignedOrUnchecked)
        )
        #expect(decision == .suppressed(reason: .unsignedOrUnchecked))
    }

    @Test("未署名の.appバンドルを実環境判定で manualOnly にする")
    func unsignedAppBundleEvaluatesManualOnly() throws {
        // Info.plistだけの最小バンドル（Developer ID署名なし）を作る。
        // 実行環境では署名情報が取れない（unsignedOrUnchecked）か
        // TeamIdentifier無し（adhocSigned）のどちらかに判定されるが、
        // どちらも manualOnly = 自動インストール抑止であることが本体。
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aub-unsigned-\(UUID().uuidString)", isDirectory: true)
        let appURL = dir.appendingPathComponent("Unsigned.app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.unsigned.app</string></dict></plist>
        """
        try plist.write(
            to: contents.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        guard let bundle = Bundle(url: appURL) else {
            Issue.record("バンドルが作れない")
            return
        }
        let eligibility = AutoUpdateEligibility.evaluate(bundle: bundle)
        guard case .manualOnly = eligibility else {
            Issue.record("manualOnly であること（Developer ID署名が無いバンドル）: \(eligibility)")
            return
        }
        #expect(eligibility != .eligible)
    }

    @Test("署名済み（eligible）でもSparkle導入前は手動ダウンロード案内になる")
    func eligibleStillManualDownloadUntilSparkle() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "2.0.0"))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0", distributionChannel: .direct)
        await service.checkNow()

        // 未確認なら確認要求
        let unconfirmed = service.requestInstall(userConfirmed: false, eligibility: .eligible)
        guard case .requiresUserConfirmation(let version, _) = unconfirmed else {
            Issue.record("requiresUserConfirmation であること: \(unconfirmed)")
            return
        }
        #expect(version == "2.0.0")

        // 確認済みでもSparkle未導入のため手動ダウンロード
        let confirmed = service.requestInstall(userConfirmed: true, eligibility: .eligible)
        #expect(confirmed == .manualDownload(pageURL: nil))
    }

    // MARK: - 手動確認は自動確認オフでも動作

    @Test("手動の更新確認は自動確認オフでも常に動作する")
    func manualCheckWorksEvenWhenAutomaticDisabled() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "1.0.0"))
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0", distributionChannel: .direct)

        await service.automaticCheckIfNeeded(enabled: false)
        #expect(provider.fetchCount == 0, "自動確認オフなら自動では確認しない")
        #expect(service.outcome == .idle)

        await service.checkNow()
        #expect(provider.fetchCount == 1, "手動確認は設定に依らず動作する")
        #expect(service.outcome == .upToDate)
    }

    // MARK: - リリース成果物の命名

    @Test("リリースファイル名の生成規則")
    func artifactNaming() {
        #expect(ReleaseArtifactNaming.zipName(version: "1.0.0", buildNumber: "1") == "AIUsageBuddy-1.0.0-1-arm64.zip")
        #expect(ReleaseArtifactNaming.zipName(version: "1.2.10", buildNumber: "34") == "AIUsageBuddy-1.2.10-34-arm64.zip")
        #expect(ReleaseArtifactNaming.dmgName(version: "1.0.0", buildNumber: "1") == "AIUsageBuddy-1.0.0-1-arm64.dmg")
        #expect(ReleaseArtifactNaming.displayName(version: "1.0.0", buildNumber: "1") == "AI Usage Buddy 1.0.0 (1)")
    }

    // MARK: - SHA-256チェックサム

    @Test("SHA-256チェックサム生成（既知ベクトル）")
    func sha256KnownVectors() {
        // "abc" のSHA-256（FIPS 180-4 既知ベクトル）
        #expect(Checksum.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // 空データ
        #expect(Checksum.sha256Hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // 64文字（256bit ÷ 4）の小文字hex
        let digest = Checksum.sha256Hex(Data("AI Usage Buddy".utf8))
        #expect(digest.count == 64)
        #expect(digest == digest.lowercased())
    }

    @Test("SHA-256チェックサム生成（ファイル読み出し）")
    func sha256FileRead() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aub-checksum-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        #expect(try Checksum.sha256Hex(contentsOf: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: - 認証情報が表に出ない

    @Test("更新確認の失敗理由にトークン等の秘密情報が含まれない")
    func failureReasonDoesNotLeakSecrets() async {
        let provider = SpyUpdateProvider()
        // メール・Bearer・トークン混じりのエラーメッセージ
        let leaked = NSError(
            domain: "UpdateTest",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "request to user@example.com failed with bearer abcdefghijklmnopqrstuvwxyz012345 and access_token=abcdefghijklmnopqrstuvwxyz0123456789ABCDEF"]
        )
        provider.setError(leaked)
        let service = UpdateService(provider: provider, defaults: makeDefaults(), currentVersion: "1.0.0", distributionChannel: .direct)

        await service.checkNow()
        guard case .failed(let reason) = service.outcome else {
            Issue.record("failed であること: \(service.outcome)")
            return
        }
        #expect(!reason.contains("user@example.com"), "メールアドレスが出ない")
        #expect(!reason.contains("abcdefghijklmnopqrstuvwxyz"), "トークン値が出ない")
        #expect(reason.contains("[redacted]"), "検閲マーカーが入る")
    }
}
