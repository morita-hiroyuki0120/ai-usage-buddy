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

/// Returns only after logout and cleanup of the owned helper have completed.
protocol AccountLogoutProviding: Sendable {
    func logoutAndStop(for account: Account) async throws
}

/// UsageProvider の公式Codex実装。アカウントごとに codex app-server をspawnして利用枠を取得する。
public final class CodexUsageProvider: @unchecked Sendable, UsageProvider, AccountLogoutProviding {

    public static let shared = CodexUsageProvider()

    private let logger = AppLogger(category: "CodexUsageProvider")
    private let distributionChannel: DistributionChannel
    private let accountStore: AccountStore
    /// アカウントごとの長寿命クライアント（プロセス再利用のため）。
    private let cache = ClientCache()

    public init(
        distributionChannel: DistributionChannel = .current,
        accountStore: AccountStore = .shared
    ) {
        self.distributionChannel = distributionChannel
        self.accountStore = accountStore
    }

    public func accounts() async throws -> [Account] {
        try accountStore.loadAccounts()
    }

    /// アカウントに対応する起動済みクライアントを取得する（なければ起動する）。
    public func runningClient(for account: Account) async throws -> CodexAppServerClient {
        let home = try codexHome(for: account)
        return try await cache.runningClient(
            for: account.id,
            codexHome: home,
            distributionChannel: distributionChannel,
            containerDirectory: accountStore.containerDirectory
        )
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
                let home = try codexHome(for: account)
                try await cache.restartClient(
                    for: account.id,
                    codexHome: home,
                    distributionChannel: distributionChannel,
                    containerDirectory: accountStore.containerDirectory,
                    expectedClient: distributionChannel.isAppStore ? client : nil
                )
                let fresh = try await cache.runningClient(
                    for: account.id,
                    codexHome: home,
                    distributionChannel: distributionChannel,
                    containerDirectory: accountStore.containerDirectory
                )
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

    func logoutAndStop(for account: Account) async throws {
        guard distributionChannel.isAppStore, account.homeKind == .managed else {
            throw CodexClientError.storeHomeInvalid
        }
        let home = try codexHome(for: account)
        try await cache.logoutAndStop(
            for: account.id,
            codexHome: home,
            containerDirectory: accountStore.containerDirectory
        )
    }

    /// アカウントのクライアントを破棄する（Direct版ではlogoutを送らない）。
    public func discardClient(for accountID: UUID) async {
        await cache.discardClient(for: accountID)
    }

    public func stopAll() async {
        await cache.stopAll()
    }

    private func codexHome(for account: Account) throws -> URL? {
        if distributionChannel.isAppStore && account.homeKind != .managed {
            throw CodexClientError.storeHomeInvalid
        }
        return account.homeKind == .managed ? accountStore.managedHomeURL(for: account.id) : nil
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
    private struct StartingClient {
        let client: CodexAppServerClient
        let task: Task<Void, Error>
        let generation: UInt64
    }

    private var clients: [UUID: CodexAppServerClient] = [:]
    private var startingClients: [UUID: StartingClient] = [:]
    private var generations: [UUID: UInt64] = [:]
    private var deletionOwners: [UUID: UUID] = [:]
    private var loggedOutAccountIDs: Set<UUID> = []
    private var isShuttingDown = false

    func runningClient(
        for id: UUID,
        codexHome: URL?,
        distributionChannel: DistributionChannel = .current,
        containerDirectory: URL? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        deletionOwner: UUID? = nil
    ) async throws -> CodexAppServerClient {
        try checkAccess(for: id, deletionOwner: deletionOwner)
        let requestGeneration = generations[id, default: 0]

        if let existing = clients[id] {
            if await existing.isAlive() {
                try checkAccess(for: id, deletionOwner: deletionOwner)
                guard generations[id, default: 0] == requestGeneration else {
                    throw CodexClientError.terminated
                }
                if clients[id] === existing { return existing }
            } else {
                if clients[id] === existing {
                    clients[id] = nil
                }
                await existing.stop()
            }
        }

        try checkAccess(for: id, deletionOwner: deletionOwner)
        guard generations[id, default: 0] == requestGeneration else {
            throw CodexClientError.terminated
        }
        if let starting = startingClients[id] {
            return try await awaitAndInstall(starting, for: id)
        }

        let generation = advanceGeneration(for: id)
        let client = CodexAppServerClient(
            codexHome: codexHome,
            distributionChannel: distributionChannel,
            bundleURL: bundleURL,
            accountID: id,
            containerDirectory: containerDirectory
        )
        let task = Task<Void, Error> {
            try Task.checkCancellation()
            try await client.start()
        }
        let starting = StartingClient(client: client, task: task, generation: generation)
        startingClients[id] = starting
        return try await awaitAndInstall(starting, for: id)
    }

    func restartClient(
        for id: UUID,
        codexHome: URL?,
        distributionChannel: DistributionChannel = .current,
        containerDirectory: URL? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        expectedClient: CodexAppServerClient? = nil
    ) async throws {
        try checkAccess(for: id)
        if let expectedClient, clients[id] !== expectedClient {
            throw CodexClientError.terminated
        }
        let discardedGeneration = generations[id, default: 0] &+ 1
        await discardClient(for: id)
        if expectedClient != nil, generations[id] != discardedGeneration {
            throw CodexClientError.terminated
        }
        _ = try await runningClient(
            for: id,
            codexHome: codexHome,
            distributionChannel: distributionChannel,
            containerDirectory: containerDirectory,
            bundleURL: bundleURL
        )
    }

    /// Reserves this account across awaits; stale fetches cannot restart its helper.
    func logoutAndStop(
        for id: UUID,
        codexHome: URL?,
        containerDirectory: URL,
        bundleURL: URL = Bundle.main.bundleURL
    ) async throws {
        guard !isShuttingDown, deletionOwners[id] == nil else {
            throw CodexClientError.terminated
        }
        let owner = UUID()
        deletionOwners[id] = owner
        defer {
            if deletionOwners[id] == owner { deletionOwners[id] = nil }
        }
        let client = try await runningClient(
            for: id,
            codexHome: codexHome,
            distributionChannel: .appStore,
            containerDirectory: containerDirectory,
            bundleURL: bundleURL,
            deletionOwner: owner
        )
        do {
            try Task.checkCancellation()
            try await client.logout()
            try Task.checkCancellation()
            guard deletionOwners[id] == owner, !isShuttingDown, clients[id] === client else {
                throw CodexClientError.terminated
            }
            // Keep stale callers blocked after success, even if local deletion later fails.
            // An explicit deletion retry may acquire a new owned logout session.
            loggedOutAccountIDs.insert(id)
        } catch {
            try await discardOwnedClient(client, for: id)
            throw error
        }
        try await discardOwnedClient(client, for: id)
    }

    private func checkAccess(for id: UUID, deletionOwner: UUID? = nil) throws {
        guard !isShuttingDown,
              deletionOwners[id] == nil || deletionOwners[id] == deletionOwner,
              !loggedOutAccountIDs.contains(id) || deletionOwner != nil else {
            throw CodexClientError.terminated
        }
    }

    private func discardOwnedClient(_ client: CodexAppServerClient, for id: UUID) async throws {
        // Unstructured cleanup does not inherit the caller's cancellation.
        // Await it so cancellation cannot skip the helper's exit wait.
        await Task { await client.stop() }.value
        guard !(await client.isAlive()) else {
            // Keep ownership for a later explicit retry/stopAll; do not delete the home.
            loggedOutAccountIDs.insert(id)
            throw CodexClientError.terminated
        }
        if clients[id] === client {
            clients[id] = nil
            _ = advanceGeneration(for: id)
        }
        if startingClients[id]?.client === client {
            startingClients.removeValue(forKey: id)?.task.cancel()
        }
    }

    func discardClient(for id: UUID) async {
        _ = advanceGeneration(for: id)
        let starting = startingClients.removeValue(forKey: id)
        let existing = clients.removeValue(forKey: id)
        starting?.task.cancel()

        if let starting {
            await starting.client.stop()
        }
        if let existing, existing !== starting?.client {
            await existing.stop()
        }
    }

    func stopAll() async {
        isShuttingDown = true
        let accountIDs = Set(clients.keys).union(startingClients.keys)
        for id in accountIDs {
            _ = advanceGeneration(for: id)
        }
        let starting = Array(startingClients.values)
        let active = Array(clients.values)
        startingClients.removeAll()
        clients.removeAll()
        for item in starting {
            item.task.cancel()
        }

        var uniqueClients: [CodexAppServerClient] = []
        var seen = Set<ObjectIdentifier>()
        for client in starting.map(\.client) + active where seen.insert(ObjectIdentifier(client)).inserted {
            uniqueClients.append(client)
        }
        await withTaskGroup(of: Void.self) { group in
            for client in uniqueClients {
                group.addTask { await client.stop() }
            }
        }
    }

    private func awaitAndInstall(
        _ starting: StartingClient,
        for id: UUID
    ) async throws -> CodexAppServerClient {
        do {
            try await starting.task.value
        } catch {
            if startingClients[id]?.generation == starting.generation {
                startingClients[id] = nil
            }
            await starting.client.stop()
            throw error
        }

        guard generations[id] == starting.generation, !isShuttingDown else {
            await starting.client.stop()
            throw CodexClientError.terminated
        }
        if let installed = clients[id] {
            guard installed === starting.client else {
                await starting.client.stop()
                throw CodexClientError.terminated
            }
            if startingClients[id]?.generation == starting.generation {
                startingClients[id] = nil
            }
            return installed
        }

        clients[id] = starting.client
        if startingClients[id]?.generation == starting.generation {
            startingClients[id] = nil
        }
        return starting.client
    }

    private func advanceGeneration(for id: UUID) -> UInt64 {
        let generation = (generations[id] ?? 0) &+ 1
        generations[id] = generation
        return generation
    }
}
