import Foundation

// MARK: - Official protocol models

/// `account/rateLimits/read` のレスポンス（公式 app-server protocol v2 スキーマ準拠）。
/// primary = 5時間枠、secondary = 週間枠。
public struct GetAccountRateLimitsResponse: Decodable, Sendable {
    public struct RateLimitWindow: Decodable, Sendable {
        /// 使用量（%）。残量は 100 - usedPercent。
        public let usedPercent: Int
        /// リセット絶対時刻（unix秒）。
        public let resetsAt: Int64?
        /// ウィンドウ長（分）。5時間枠は 300、週間枠は 10080。
        public let windowDurationMins: Int64?
    }

    public struct RateLimitSnapshot: Decodable, Sendable {
        public let limitId: String?
        public let primary: RateLimitWindow?
        public let secondary: RateLimitWindow?
        public let planType: String?
    }

    public let accountId: String?
    public let rateLimits: RateLimitSnapshot

    /// primary のウィンドウ長が5時間（300分）であることを公式値から確認する。
    public var fiveHourWindowIsPrimary: Bool {
        guard let mins = rateLimits.primary?.windowDurationMins else { return true }
        return mins == 300
    }
}

// MARK: - Provider

/// UsageProvider の公式Codex実装。アカウントごとに codex app-server をspawnして利用枠を取得する。
public final class CodexUsageProvider: @unchecked Sendable, UsageProvider {

    public static let shared = CodexUsageProvider()

    private let logger = AppLogger(category: "CodexUsageProvider")
    /// アカウントごとの長寿命クライアント（プロセス再利用のため）。
    private let cache = ClientCache()

    public init() {}

    public func accounts() async throws -> [Account] {
        try AccountStore.shared.loadAccounts()
    }

    /// アカウントに対応する起動済みクライアントを取得する（なければ起動する）。
    public func runningClient(for account: Account) async throws -> CodexAppServerClient {
        let home = account.homeKind == .managed ? AccountStore.shared.managedHomeURL(for: account.id) : nil
        return try await cache.runningClient(for: account.id, codexHome: home)
    }

    public func fetchSnapshot(for account: Account) async throws -> UsageSnapshot {
        let client = try await runningClient(for: account)

        let limits: GetAccountRateLimitsResponse
        do {
            limits = try await client.readRateLimits()
        } catch let error as CodexClientError {
            if case .serverError(_, let message) = error,
               message.localizedCaseInsensitiveContains("authentication required") {
                throw CodexClientError.authenticationRequired
            }
            if case .authenticationRequired = error {
                throw error
            }
            // プロセスが死んでいた場合は再起動して1回だけリトライ
            if !(await client.isAlive()) {
                logger.info("app-server died; restarting for retry")
                try await cache.restartClient(for: account.id, codexHome: account.resolvedCodexHome)
                let fresh = try await cache.runningClient(for: account.id, codexHome: account.resolvedCodexHome)
                limits = try await fresh.readRateLimits()
            } else {
                throw error
            }
        }

        let now = Date()
        var snapshot = UsageSnapshot(accountID: account.id, fetchedAt: now)

        if let primary = limits.rateLimits.primary {
            snapshot.fiveHour = QuotaWindow(
                kind: .fiveHour,
                remainingPercent: 100 - primary.usedPercent,
                resetAt: primary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                fetchedAt: now,
                state: .fresh
            )
        }
        if let secondary = limits.rateLimits.secondary {
            snapshot.weekly = QuotaWindow(
                kind: .weekly,
                remainingPercent: 100 - secondary.usedPercent,
                resetAt: secondary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                fetchedAt: now,
                state: .fresh
            )
        }
        snapshot.planType = limits.rateLimits.planType
        return snapshot
    }

    public func fetchAccountInfo(for account: Account) async throws -> Account {
        let client = try await runningClient(for: account)
        let response = try await client.readAccount()
        guard let info = response.account else {
            return account
        }
        var updated = account
        updated.officialEmail = info.email
        updated.officialPlanType = info.planType
        return updated
    }

    /// アカウントのクライアントを破棄する（アカウント削除時）。
    public func discardClient(for accountID: UUID) async {
        await cache.discardClient(for: accountID)
    }
}

extension Account {
    /// managed アカウントの CODEX_HOME（アプリ管理ディレクトリ）。
    public var resolvedCodexHome: URL? {
        homeKind == .managed ? AccountStore.shared.managedHomeURL(for: id) : nil
    }
}

/// アカウントごとのクライアントキャッシュ。
actor ClientCache {
    private var clients: [UUID: CodexAppServerClient] = [:]

    func runningClient(for id: UUID, codexHome: URL?) async throws -> CodexAppServerClient {
        if let existing = clients[id] {
            if await existing.isAlive() {
                return existing
            }
            await existing.stop()
            clients[id] = nil
        }
        let client = CodexAppServerClient(codexHome: codexHome)
        try await client.start()
        clients[id] = client
        return client
    }

    func restartClient(for id: UUID, codexHome: URL?) async throws {
        if let existing = clients[id] {
            await existing.stop()
            clients[id] = nil
        }
        let client = CodexAppServerClient(codexHome: codexHome)
        try await client.start()
        clients[id] = client
    }

    func discardClient(for id: UUID) async {
        if let existing = clients.removeValue(forKey: id) {
            await existing.stop()
        }
    }
}
