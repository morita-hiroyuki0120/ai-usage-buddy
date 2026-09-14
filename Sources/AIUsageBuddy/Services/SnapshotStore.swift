import Foundation

/// スナップショット・手動補正・通知送信済みキーの永続化。
public final class SnapshotStore: @unchecked Sendable {

    public static let shared = SnapshotStore()

    struct PersistedState: Codable {
        var snapshots: [UUID: UsageSnapshot] = [:]
        /// アカウント+リミット単位の手動補正値（0〜100）。
        var manualOverrides: [String: ManualOverride] = [:]
        /// 送信済み通知キー（アカウント|リミット|しきい値|リセット時刻）。
        var notifiedKeys: Set<String> = []
    }

    /// 手動補正値。
    public struct ManualOverride: Codable, Equatable, Sendable {
        public var percent: Int
        public var appliedAt: Date
    }

    private var state = PersistedState()
    private let fileURL: URL
    private let lock = NSLock()
    private let logger = AppLogger(category: "SnapshotStore")

    public init(containerDirectory: URL? = nil) {
        let base = containerDirectory ?? AccountStore.defaultContainer()
        self.fileURL = base.appendingPathComponent("snapshots.json")
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let loaded = try? decoder.decode(PersistedState.self, from: data) {
                self.state = loaded
            }
        }
    }

    // MARK: - Snapshots

    public func snapshot(for accountID: UUID) -> UsageSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return state.snapshots[accountID]
    }

    public func allSnapshots() -> [UUID: UsageSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return state.snapshots
    }

    /// 公式取得成功時に呼ぶ。手動補正を解除してスナップショットを更新する。
    public func storeOfficialSnapshot(_ snapshot: UsageSnapshot) {
        lock.lock()
        state.snapshots[snapshot.accountID] = snapshot
        clearManualOverridesLocked(accountID: snapshot.accountID)
        persistLocked()
        lock.unlock()
    }

    /// 取得失敗時に呼ぶ。前回値を stale 表示へ切り替え、エラー種別と
    /// 検閲済みの詳細メッセージを記録する（認証情報・秘密URLは含めない）。
    public func markStale(accountID: UUID, kind: UsageErrorKind, detail: String?, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard var snapshot = state.snapshots[accountID] else { return }
        if snapshot.fiveHour?.state != .manual {
            snapshot.fiveHour?.state = .stale
        }
        if snapshot.weekly?.state != .manual {
            snapshot.weekly?.state = .stale
        }
        snapshot.lastErrorKind = kind
        snapshot.lastErrorMessage = detail.map { LogRedactor.scrub($0) }
        state.snapshots[accountID] = snapshot
        persistLocked()
    }

    // MARK: - Manual overrides

    static func overrideKey(accountID: UUID, kind: QuotaLimitKind) -> String {
        "\(accountID.uuidString)|\(kind.rawValue)"
    }

    /// 手動補正を設定する（自動取得が一時的に失敗した場合のみの運用）。
    public func setManualOverride(accountID: UUID, kind: QuotaLimitKind, percent: Int, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        let clamped = max(0, min(100, percent))
        state.manualOverrides[Self.overrideKey(accountID: accountID, kind: kind)] = ManualOverride(percent: clamped, appliedAt: now)
        // スナップショットの該当リミットを manual 状態にする（リセット時刻は既存値を維持）
        var snapshot = state.snapshots[accountID] ?? UsageSnapshot(accountID: accountID)
        var window = snapshot.window(for: kind) ?? QuotaWindow(kind: kind, remainingPercent: clamped, resetAt: nil, fetchedAt: now, state: .manual)
        window.remainingPercent = clamped
        window.state = .manual
        window.fetchedAt = now
        switch kind {
        case .fiveHour: snapshot.fiveHour = window
        case .weekly: snapshot.weekly = window
        }
        state.snapshots[accountID] = snapshot
        persistLocked()
    }

    public func manualOverride(accountID: UUID, kind: QuotaLimitKind) -> ManualOverride? {
        lock.lock(); defer { lock.unlock() }
        return state.manualOverrides[Self.overrideKey(accountID: accountID, kind: kind)]
    }

    public func hasManualOverride(accountID: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let prefix = accountID.uuidString + "|"
        return state.manualOverrides.keys.contains { $0.hasPrefix(prefix) }
    }

    /// 手動補正をクリアする（公式値へ戻す）。
    public func clearManualOverride(accountID: UUID, kind: QuotaLimitKind) {
        lock.lock()
        defer { lock.unlock() }
        state.manualOverrides.removeValue(forKey: Self.overrideKey(accountID: accountID, kind: kind))
        if var snapshot = state.snapshots[accountID],
           var window = snapshot.window(for: kind), window.state == .manual {
            window.state = .stale
            switch kind {
            case .fiveHour: snapshot.fiveHour = window
            case .weekly: snapshot.weekly = window
            }
            state.snapshots[accountID] = snapshot
        }
        persistLocked()
    }

    private func clearManualOverridesLocked(accountID: UUID) {
        let prefix = accountID.uuidString + "|"
        state.manualOverrides = state.manualOverrides.filter { !$0.key.hasPrefix(prefix) }
    }

    // MARK: - Notification bookkeeping

    static func notificationKey(accountID: UUID, kind: QuotaLimitKind, threshold: Int, resetAt: Date?) -> String {
        let resetStamp = resetAt.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown"
        return "\(accountID.uuidString)|\(kind.rawValue)|\(threshold)|\(resetStamp)"
    }

    public func hasNotified(key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state.notifiedKeys.contains(key)
    }

    public func markNotified(key: String) {
        lock.lock()
        defer { lock.unlock() }
        state.notifiedKeys.insert(key)
        pruneNotifiedKeysLocked()
        persistLocked()
    }

    /// リセット済み（resetAt を過ぎた）通知キーを破棄し、次のウィンドウで再通知を可能にする。
    private func pruneNotifiedKeysLocked(now: Date = Date()) {
        state.notifiedKeys = state.notifiedKeys.filter { key in
            guard let stampString = key.split(separator: "|").last, stampString != "unknown" else { return true }
            guard let stamp = TimeInterval(stampString) else { return true }
            return Date(timeIntervalSince1970: stamp) > now
        }
    }

    // MARK: - Persistence

    private func persistLocked() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("failed to persist snapshots: \(error.localizedDescription)")
        }
    }
}
