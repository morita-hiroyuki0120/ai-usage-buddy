import Foundation

// MARK: - Release configuration

/// リリース設定。`scripts/build-app.sh` が `config/ReleaseConfig.xcconfig` の値を
/// Info.plist へ注入したものを Bundle 経由で読み取る。
/// 秘密情報は含まない（所有者名・リポジトリ名・URL・バージョン番号のみ）。
public struct ReleaseConfiguration: Equatable, Sendable {

    /// Approved public support destination; independent of updater configuration.
    public static let storeSupportURL: URL? = URL(
        string: "https://github.com/morita-hiroyuki0120/ai-usage-buddy/issues"
    )

    /// GitHub所有者。未設定（空・プレースホルダー）は `nil`。
    /// 未設定の間は更新確認の通信を行わない（手動更新モード）。
    public let githubOwner: String?
    /// リポジトリ名。
    public let githubRepository: String
    /// アプリバージョン（CFBundleShortVersionString）。
    public let appVersion: String
    /// ビルド番号（CFBundleVersion）。
    public let buildNumber: String
    /// Sparkle 2 Appcast URL（HTTPSのみ・プレースホルダー拒否）。導入は後続作業。
    public let sparkleAppcastURL: URL?

    public init(
        githubOwner: String?,
        githubRepository: String,
        appVersion: String,
        buildNumber: String,
        sparkleAppcastURL: URL? = nil
    ) {
        self.githubOwner = githubOwner
        self.githubRepository = githubRepository
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.sparkleAppcastURL = sparkleAppcastURL
    }

    /// 未設定を表すプレースホルダー値（xcconfig / Info.plist に書かれ得る）。
    public static let placeholderOwnerValue = "YOUR_GITHUB_OWNER"
    public static let placeholderAppcastValue = "https://example.com/aiusagebuddy-appcast.xml"

    /// Bundle の Info.plist から生成する。テストランナー等バンドル情報が無い場合は
    /// 未設定扱い（owner=nil・バージョンは "0.0.0"）で、更新確認は手動モードになる。
    public static func from(bundle: Bundle = .main) -> ReleaseConfiguration {
        let info = bundle.infoDictionary
        let owner = normalizeOwner(info?["GitHubOwner"] as? String)
        let repository = nonEmpty(info?["GitHubRepository"] as? String)
            ?? GitHubReleasesProvider.defaultRepository
        let version = nonEmpty(info?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let build = nonEmpty(info?["CFBundleVersion"] as? String) ?? "0"
        let appcast = validAppcastURL(info?["SparkleAppcastURL"] as? String)
        return ReleaseConfiguration(
            githubOwner: owner,
            githubRepository: repository,
            appVersion: version,
            buildNumber: build,
            sparkleAppcastURL: appcast
        )
    }

    /// 未設定時に更新確認へ渡す所有者（プレースホルダー = 通信しない）。
    public var effectiveGitHubOwner: String {
        githubOwner ?? GitHubReleasesProvider.placeholderOwner
    }

    /// GitHub所有者が設定済みか（未設定なら更新確認は手動モード）。
    public var isGitHubConfigured: Bool {
        githubOwner != nil
    }

    /// GitHub Releases の最新リリースページURL（設定済みの場合のみ。手動更新の案内用）。
    public var releasesPageURL: URL? {
        guard let owner = githubOwner else { return nil }
        return URL(string: "https://github.com/\(owner)/\(githubRepository)/releases/latest")
    }

    // MARK: - 正規化（純粋関数）

    /// 所有者の正規化: nil / 空 / プレースホルダーは未設定（nil）。
    static func normalizeOwner(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != placeholderOwnerValue else { return nil }
        return trimmed
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Appcast URLの検証: 空は未設定（nil）、**HTTPSのみ許可**、プレースホルダー拒否、host必須。
    static func validAppcastURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard raw != placeholderAppcastValue else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

// MARK: - GitHubReleasesProvider bridge

extension GitHubReleasesProvider {

    /// ReleaseConfiguration から取得元を組み立てる（未設定はプレースホルダー=通信しない）。
    public init(configuration: ReleaseConfiguration, urlSession: URLSession = .shared) {
        self.init(
            owner: configuration.effectiveGitHubOwner,
            repository: configuration.githubRepository,
            urlSession: urlSession
        )
    }
}

// MARK: - Artifact naming

/// リリース成果物のファイル名規則。`scripts/package-release.sh` / `scripts/create-dmg.sh`
/// と同じ命名（アーティファクト名の変更はここを変え、スクリプト側も合わせる）。
public enum ReleaseArtifactNaming {

    /// 例: "AIUsageBuddy-1.0.0-1-arm64.zip"
    public static func zipName(version: String, buildNumber: String) -> String {
        "AIUsageBuddy-\(version)-\(buildNumber)-arm64.zip"
    }

    /// 例: "AIUsageBuddy-1.0.0-1-arm64.dmg"
    public static func dmgName(version: String, buildNumber: String) -> String {
        "AIUsageBuddy-\(version)-\(buildNumber)-arm64.dmg"
    }

    /// 例: "AI Usage Buddy 1.0.0 (1)"
    public static func displayName(version: String, buildNumber: String) -> String {
        "AI Usage Buddy \(version) (\(buildNumber))"
    }
}
