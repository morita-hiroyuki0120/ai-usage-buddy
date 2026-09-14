import Foundation
import Combine
import AppKit
import Security

// MARK: - Release model

/// 取得した最新リリースの情報。
public struct UpdateRelease: Equatable, Sendable {
    /// タグ名（"v" 接頭辞は正規化済み）。
    public let version: String
    /// リリースページURL。
    public let pageURL: URL?
    /// リリースノート。
    public let notes: String?

    public init(version: String, pageURL: URL? = nil, notes: String? = nil) {
        self.version = version
        self.pageURL = pageURL
        self.notes = notes
    }
}

// MARK: - Provider errors

public enum UpdateProviderError: Error, Equatable, Sendable {
    /// GitHub所有者が未設定（プレースホルダーのまま）。
    case notConfigured
    /// HTTPエラー。
    case server(status: Int)
    /// 応答形状が不正。
    case invalidResponse
}

// MARK: - Provider protocol

/// 更新情報の取得元の抽象。将来は GitHub Releases + Sparkle 2 (Appcast / EdDSA署名) に
/// 差し替えられるよう、HTTPSでのリリース取得のみに責任を持たせる。
public protocol UpdateProviding: Sendable {
    func fetchLatestRelease() async throws -> UpdateRelease
}

// MARK: - Version comparison

/// バージョン文字列の比較（純粋関数）。"1.10.0" > "1.9.0" を数値比較で正しく判定する。
public enum VersionCompare {

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = numericComponents(lhs)
        let right = numericComponents(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    /// "v1.2.3" → [1, 2, 3]。数値でない断片は0として扱う。
    static func numericComponents(_ version: String) -> [Int] {
        var text = Substring(version)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text = text.dropFirst()
        }
        return text.split(separator: ".").map { component in
            let digits = component.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }
}

// MARK: - GitHub Releases provider

/// GitHub Releases から最新版を取得する実装（HTTPSのみ・非公開API不使用）。
/// 所有者がプレースホルダーの間は `.notConfigured` を返し、UIは手動案内を表示する。
/// ※ 所有者は未指定（README参照）。READMEの指示に従って設定すること。
public struct GitHubReleasesProvider: UpdateProviding {

    /// 所有者未設定を表すプレースホルダー。
    public static let placeholderOwner = "YOUR_GITHUB_OWNER"
    /// このリポジトリのリポジトリ名。
    public static let defaultRepository = "ai-usage-buddy"

    public let owner: String
    public let repository: String
    public let urlSession: URLSession

    public init(
        owner: String = GitHubReleasesProvider.placeholderOwner,
        repository: String = GitHubReleasesProvider.defaultRepository,
        urlSession: URLSession = .shared
    ) {
        self.owner = owner
        self.repository = repository
        self.urlSession = urlSession
    }

    public func fetchLatestRelease() async throws -> UpdateRelease {
        guard owner != Self.placeholderOwner, !owner.isEmpty else {
            throw UpdateProviderError.notConfigured
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest") else {
            throw UpdateProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateProviderError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateProviderError.server(status: http.statusCode)
        }

        struct Payload: Decodable {
            let tag_name: String?
            let html_url: String?
            let body: String?
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UpdateProviderError.invalidResponse
        }
        guard var tag = payload.tag_name, !tag.isEmpty else {
            throw UpdateProviderError.invalidResponse
        }
        if tag.hasPrefix("v") || tag.hasPrefix("V") {
            tag.removeFirst()
        }
        return UpdateRelease(
            version: tag,
            pageURL: payload.html_url.flatMap(URL.init(string:)),
            notes: payload.body
        )
    }
}

// MARK: - Auto-update eligibility

/// 自動インストールの可否。
/// Developer ID署名・公証が済むまで、このアプリは「更新確認＋GitHub Releases手動案内」のみ。
public enum AutoUpdateEligibility: Equatable, Sendable {

    public enum ManualReason: String, Equatable, Sendable {
        /// .app バンドル外での実行（開発ビルド等）。
        case notAppBundle = "notAppBundle"
        /// 署名が無い、または検査できない。
        case unsignedOrUnchecked = "unsignedOrUnchecked"
        /// ad-hoc署名（TeamIdentifierが無い）。
        case adhocSigned = "adhocSigned"
    }

    /// 自動更新の実施が許可される状態（Developer ID署名済み。公証確認は署名導入時に追加予定）。
    case eligible
    /// 手動ダウンロード案内のみ。
    case manualOnly(reason: ManualReason)

    /// 実行中のプロセスの署名状態から判定する。
    public static func evaluate(bundle: Bundle = .main) -> AutoUpdateEligibility {
        guard bundle.bundleIdentifier != nil, bundle.bundleURL.pathExtension == "app" else {
            return .manualOnly(reason: .notAppBundle)
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return .manualOnly(reason: .unsignedOrUnchecked)
        }
        var infoDictionary: CFDictionary?
        let flags = SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticCode, flags, &infoDictionary) == errSecSuccess,
              let info = infoDictionary as? [String: Any] else {
            return .manualOnly(reason: .unsignedOrUnchecked)
        }
        // ad-hoc署名には TeamIdentifier が付かない
        guard let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else {
            return .manualOnly(reason: .adhocSigned)
        }
        return .eligible
    }
}

// MARK: - Service

/// 更新確認の状態管理。確認は1日1回まで（設定で自動確認オフ可）。
@MainActor
public final class UpdateService: ObservableObject {

    public static let lastCheckKey = "com.aiusagebuddy.app.lastUpdateCheckAt"
    /// 自動確認の最小間隔（24時間）。
    public static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    /// 更新確認の結果。
    public enum Outcome: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case available(version: String, pageURL: URL?)
        /// GitHub所有者が未設定（手動でReleasesを確認する案内を表示）。
        case notConfigured
        case failed(reason: String)
    }

    /// インストール要求の結果。
    public enum InstallDecision: Equatable, Sendable {
        /// ad-hoc署名等では自動インストールしない。
        case suppressed(reason: AutoUpdateEligibility.ManualReason)
        /// ユーザー確認が必要。
        case requiresUserConfirmation(version: String, pageURL: URL?)
        /// 現段階の正式な導線: GitHub Releases の手動ダウンロード。
        case manualDownload(pageURL: URL?)
    }

    @Published public private(set) var outcome: Outcome = .idle

    public let currentVersion: String
    private let provider: UpdateProviding
    private let defaults: UserDefaults
    private let now: () -> Date

    /// - Parameters:
    ///   - provider: 省略時は ReleaseConfiguration（Info.plist）から組み立てた
    ///     GitHubReleasesProvider。GitHub所有者が未設定なら通信しない（`.notConfigured`）。
    ///   - currentVersion: 省略時は ReleaseConfiguration（CFBundleShortVersionString）。
    public init(
        provider: UpdateProviding? = nil,
        defaults: UserDefaults = .standard,
        currentVersion: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let configuration = ReleaseConfiguration.from()
        self.provider = provider ?? GitHubReleasesProvider(configuration: configuration)
        self.defaults = defaults
        self.currentVersion = currentVersion ?? configuration.appVersion
        self.now = now
    }

    /// 前回の確認から24時間経っていなければ確認しない（自動確認用）。
    /// 設定で自動確認がオフなら何もしない。
    public func automaticCheckIfNeeded(enabled: Bool) async {
        guard enabled else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           now().timeIntervalSince(last) < Self.automaticCheckInterval {
            return
        }
        await checkNow()
    }

    /// 即時確認（手動・自動共通の本体）。確認を試みた時刻を記録する。
    public func checkNow() async {
        outcome = .checking
        defaults.set(now(), forKey: Self.lastCheckKey)

        let release: UpdateRelease
        do {
            release = try await provider.fetchLatestRelease()
        } catch UpdateProviderError.notConfigured {
            outcome = .notConfigured
            return
        } catch {
            outcome = .failed(reason: LogRedactor.scrub(error.localizedDescription))
            return
        }
        if VersionCompare.isNewer(release.version, than: currentVersion) {
            outcome = .available(version: release.version, pageURL: release.pageURL)
        } else {
            outcome = .upToDate
        }
    }

    /// インストール（更新）要求。ad-hoc署名・未署名では自動インストールを抑止する。
    /// 更新は必ずユーザー確認（userConfirmed）を経由する。
    /// - Parameter eligibility: 署名状態の判定（省略時は実行中のプロセスから判定）。
    public func requestInstall(
        userConfirmed: Bool,
        eligibility: AutoUpdateEligibility? = nil
    ) -> InstallDecision {
        switch eligibility ?? AutoUpdateEligibility.evaluate() {
        case .manualOnly(let reason):
            return .suppressed(reason: reason)
        case .eligible:
            guard userConfirmed else {
                let pageURL: URL?
                if case .available(_, let url) = outcome {
                    pageURL = url
                } else {
                    pageURL = nil
                }
                return .requiresUserConfirmation(version: latestVersion ?? currentVersion, pageURL: pageURL)
            }
            // Developer ID署名・公証と Sparkle 2 導入までは自動インストールを提供しない。
            // 確認済みユーザーにも手動ダウンロードページへの導線を返す。
            return manualDownloadDecision()
        }
    }

    /// 更新が見つかっている場合のバージョン。
    public var latestVersion: String? {
        if case .available(let version, _) = outcome {
            return version
        }
        return nil
    }

    private func manualDownloadDecision() -> InstallDecision {
        let pageURL: URL?
        if case .available(_, let url) = outcome {
            pageURL = url
        } else {
            pageURL = nil
        }
        return .manualDownload(pageURL: pageURL)
    }

    /// リリースページを既定のブラウザで開く（手動ダウンロード案内）。
    @discardableResult
    public func openReleasePage() -> Bool {
        if case .available(_, let url) = outcome, let url {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }
}
