import Foundation
import Testing
@testable import AIUsageBuddy

private actor DeletionSessionFixture {
    let logoutGate: AsyncTestGate?
    let stopGate: AsyncTestGate?
    let fails: Bool
    private var events: [String] = []

    init(logoutGate: AsyncTestGate? = nil, stopGate: AsyncTestGate? = nil, fails: Bool = false) {
        self.logoutGate = logoutGate
        self.stopGate = stopGate
        self.fails = fails
    }

    func logoutAndStop() async throws {
        events.append("logout")
        if let logoutGate { await logoutGate.pause() }
        events.append(fails ? "logout-failed" : "logout-succeeded")
        events.append("stop")
        if let stopGate { await stopGate.pause() }
        events.append("stopped")
        if fails { throw CodexClientError.invalidResponse("fixture-sensitive-detail") }
    }

    func recordedEvents() -> [String] { events }
}

@Suite
@MainActor
struct StoreAccountDeletionTests {
    private func makeEnvironment(channel: DistributionChannel = .appStore) async throws -> (TestEnv, Account, URL) {
        let account = Account(displayName: "Deletion fixture", homeKind: .managed)
        var snapshot = UsageSnapshot(accountID: account.id)
        snapshot.fiveHour = QuotaWindow(
            kind: .fiveHour, remainingPercent: 40, resetAt: nil, fetchedAt: Date(), state: .fresh
        )
        let env = TestEnvironment.make(accounts: [account], snapshots: [snapshot], distributionChannel: channel)
        let home = try env.model.accountStore.prepareManagedHome(for: account.id)
        try Data("fixture-only".utf8).write(to: home.appendingPathComponent("marker.fixture"))
        await env.model.refreshAll(sendNotifications: false)
        env.model.snapshotStore.setManualOverride(accountID: account.id, kind: .weekly, percent: 25, now: Date())
        var settings = env.model.settingsStore.settings
        settings.selectedAccountID = account.id
        settings.displayLimitByAccount[account.id] = .weekly
        env.model.settingsStore.settings = settings
        return (env, account, home)
    }

    private func expectRetained(_ env: TestEnv, account: Account, home: URL) throws {
        #expect(env.model.accounts.map(\.id) == [account.id])
        #expect(try env.model.accountStore.loadAccounts().map(\.id) == [account.id])
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("marker.fixture").path))
        #expect(SnapshotStore(containerDirectory: env.container).snapshot(for: account.id)?.fiveHour?.remainingPercent == 40)
        #expect(env.model.snapshots[account.id]?.fiveHour?.remainingPercent == 40)
        #expect(env.model.snapshotStore.hasManualOverride(accountID: account.id))
        let settings = SettingsStore(containerDirectory: env.container).settings
        #expect(settings.selectedAccountID == account.id)
        #expect(settings.displayLimitByAccount[account.id] == .weekly)
    }

    @Test("Store deletion waits for logout and owned stop; duplicate deletion sends no extra RPC")
    func successOrderAndDuplicateDeletion() async throws {
        let (env, account, home) = try await makeEnvironment()
        defer { try? FileManager.default.removeItem(at: env.container) }
        let logoutGate = AsyncTestGate()
        let stopGate = AsyncTestGate()
        let session = DeletionSessionFixture(logoutGate: logoutGate, stopGate: stopGate)
        env.provider.setLogoutHandler { _ in try await session.logoutAndStop() }
        let deletion = Task { await env.model.deleteAccount(account.id) }
        await logoutGate.waitForArrival()
        try expectRetained(env, account: account, home: home)
        await env.model.deleteAccount(account.id)
        #expect(env.provider.logoutCallCount == 1)
        await logoutGate.release()
        await stopGate.waitForArrival()
        #expect(await session.recordedEvents() == ["logout", "logout-succeeded", "stop"])
        try expectRetained(env, account: account, home: home)
        await stopGate.release()
        await deletion.value
        #expect(await session.recordedEvents().last == "stopped")
        #expect(env.model.accounts.isEmpty)
        #expect(try env.model.accountStore.loadAccounts().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.path))
        #expect(SnapshotStore(containerDirectory: env.container).snapshot(for: account.id) == nil)
        #expect(!env.model.snapshotStore.hasManualOverride(accountID: account.id))
        #expect(env.model.settingsStore.settings.displayLimitByAccount[account.id] == nil)
        #expect(env.model.accountDeletionErrorMessage == nil)
        await env.model.deleteAccount(account.id)
        #expect(env.provider.logoutCallCount == 1)
    }

    @Test("Logout failure waits for cleanup and retains account, home, snapshot and settings")
    func failurePreservesDataAndUsesFixedMessage() async throws {
        let (env, account, home) = try await makeEnvironment()
        defer { try? FileManager.default.removeItem(at: env.container) }
        let stopGate = AsyncTestGate()
        let session = DeletionSessionFixture(stopGate: stopGate, fails: true)
        env.provider.setLogoutHandler { _ in try await session.logoutAndStop() }
        let deletion = Task { await env.model.deleteAccount(account.id) }
        await stopGate.waitForArrival()
        try expectRetained(env, account: account, home: home)
        #expect(env.model.accountDeletionErrorMessage == nil)
        await stopGate.release()
        await deletion.value
        try expectRetained(env, account: account, home: home)
        #expect(await session.recordedEvents() == ["logout", "logout-failed", "stop", "stopped"])
        #expect(env.model.accountDeletionErrorMessage == L("settings.delete.logoutFailure"))
        #expect(!(env.model.accountDeletionErrorMessage ?? "").contains("fixture-sensitive-detail"))
    }

    @Test("Direct managed deletion never logs out the external account")
    func directDeletionDoesNotLogout() async throws {
        let (env, account, home) = try await makeEnvironment(channel: .direct)
        defer { try? FileManager.default.removeItem(at: env.container) }
        env.provider.setLogoutHandler { _ in throw CodexClientError.authenticationRequired }
        await env.model.deleteAccount(account.id)
        #expect(env.provider.logoutCallCount == 0)
        #expect(env.model.accounts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.path))
        #expect(env.model.accountDeletionErrorMessage == nil)
    }

    @Test("Store logout without an available provider fails closed")
    func unavailableLogoutKeepsData() async throws {
        let (env, account, home) = try await makeEnvironment()
        defer { try? FileManager.default.removeItem(at: env.container) }
        await env.model.deleteAccount(account.id)
        try expectRetained(env, account: account, home: home)
        #expect(env.model.accountDeletionErrorMessage == L("settings.delete.logoutFailure"))
    }

    @Test("A stale Store fetch cannot restore deleted data or overwrite data kept after failed logout", arguments: [false, true])
    func staleFetchCannotCommit(fails: Bool) async throws {
        let (env, account, home) = try await makeEnvironment()
        defer { try? FileManager.default.removeItem(at: env.container) }
        var newer = UsageSnapshot(accountID: account.id)
        newer.fiveHour = QuotaWindow(
            kind: .fiveHour, remainingPercent: 90, resetAt: nil, fetchedAt: Date(), state: .fresh
        )
        env.provider.setSnapshot(newer)
        let fetchGate = AsyncTestGate()
        env.provider.setSnapshotGate(fetchGate)
        let session = DeletionSessionFixture(fails: fails)
        env.provider.setLogoutHandler { _ in try await session.logoutAndStop() }
        let refresh = Task { await env.model.refreshAll(sendNotifications: true) }
        await fetchGate.waitForArrival()
        await env.model.deleteAccount(account.id)
        await fetchGate.release()
        await refresh.value
        if fails {
            try expectRetained(env, account: account, home: home)
        } else {
            #expect(env.model.accounts.isEmpty)
            #expect(try env.model.accountStore.loadAccounts().isEmpty)
            #expect(SnapshotStore(containerDirectory: env.container).snapshot(for: account.id) == nil)
            #expect(!FileManager.default.fileExists(atPath: home.path))
        }
        #expect(env.spy.sentNotifications.isEmpty)
    }

    @Test("Cancellation during cleanup preserves local data after the session stops")
    func cancellationKeepsData() async throws {
        let (env, account, home) = try await makeEnvironment()
        defer { try? FileManager.default.removeItem(at: env.container) }
        let stopGate = AsyncTestGate()
        let session = DeletionSessionFixture(stopGate: stopGate)
        env.provider.setLogoutHandler { _ in try await session.logoutAndStop() }
        let deletion = Task { await env.model.deleteAccount(account.id) }
        await stopGate.waitForArrival()
        deletion.cancel()
        await stopGate.release()
        await deletion.value
        #expect(await session.recordedEvents().last == "stopped")
        try expectRetained(env, account: account, home: home)
        #expect(env.model.accountDeletionErrorMessage == L("settings.delete.logoutFailure"))
    }
}
