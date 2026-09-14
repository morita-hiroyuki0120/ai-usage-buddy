import Foundation

/// アカウントの登録情報とアプリ管理の CODEX_HOME を永続化するストア。
public final class AccountStore: @unchecked Sendable {

    public static let shared = AccountStore()

    /// テストで差し替え可能にするためのフック。
    static var sharedOverride: AccountStore?

    static var current: AccountStore {
        sharedOverride ?? shared
    }

    private let queue = DispatchQueue(label: "com.aiusagebuddy.app.accountstore")
    private let fileURL: URL
    private let homesDirectory: URL
    private var cachedAccounts: [Account]?
    private let logger = AppLogger(category: "AccountStore")

    public init(containerDirectory: URL? = nil) {
        let base = containerDirectory ?? Self.defaultContainer()
        self.fileURL = base.appendingPathComponent("accounts.json")
        self.homesDirectory = base.appendingPathComponent("Homes", isDirectory: true)
    }

    static func defaultContainer() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("AIUsageBuddy", isDirectory: true)
    }

    // MARK: - Paths

    /// managed アカウント用の CODEX_HOME ディレクトリ。
    public func managedHomeURL(for id: UUID) -> URL {
        homesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: - CRUD

    public func loadAccounts() throws -> [Account] {
        if let cachedAccounts { return cachedAccounts }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let accounts = try JSONDecoder().decode([Account].self, from: data)
            queue.sync { cachedAccounts = accounts }
            return accounts
        } catch {
            logger.error("failed to load accounts: \(error.localizedDescription)")
            return []
        }
    }

    public func saveAccounts(_ accounts: [Account]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(accounts)
        try data.write(to: fileURL, options: .atomic)
        queue.sync { cachedAccounts = accounts }
    }

    public func upsert(_ account: Account) throws {
        var accounts = try loadAccounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        try saveAccounts(accounts)
    }

    /// アカウントを削除し、managed の場合は CODEX_HOME ごと破棄する。
    /// 既定ホーム（~/.codex）を参照するアカウントではホーム自体は削除しない。
    public func delete(accountID: UUID) throws {
        var accounts = try loadAccounts()
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let account = accounts.remove(at: index)
        try saveAccounts(accounts)
        if account.homeKind == .managed {
            let home = managedHomeURL(for: accountID)
            try? FileManager.default.removeItem(at: home)
        }
    }

    /// managed アカウント追加用に CODEX_HOME を作成する。
    public func prepareManagedHome(for id: UUID) throws -> URL {
        let home = managedHomeURL(for: id)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
}
