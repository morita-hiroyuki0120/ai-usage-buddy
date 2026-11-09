import Foundation

// MARK: - Limit kinds

/// 表示対象となる利用枠の種別。
public enum QuotaLimitKind: String, Codable, CaseIterable, Sendable {
    case fiveHour
    case weekly

    public var localizedNameKey: String {
        switch self {
        case .fiveHour: return "limit.fiveHour"
        case .weekly: return "limit.weekly"
        }
    }
}

// MARK: - QuotaWindow

/// 取得した利用枠の状態。
public enum QuotaWindowState: String, Codable, Sendable {
    /// 直近の自動取得に成功した公式値。
    case fresh
    /// 自動取得が失敗し、前回値を表示している状態。
    case stale
    /// ユーザーによる手動補正値を表示している状態。
    case manual
}

/// 1つの利用枠（5時間または週間）のスナップショット。
public struct QuotaWindow: Codable, Equatable, Sendable {
    public var kind: QuotaLimitKind
    /// 0〜100に正規化した残量（公式値は usedPercent のため 100 - usedPercent）。
    public var remainingPercent: Int
    /// 公式から取得したリセット絶対時刻。アプリ側で推定しない。
    public var resetAt: Date?
    /// この値を取得した時刻（手動補正時は補正した時刻）。
    public var fetchedAt: Date
    public var state: QuotaWindowState

    public init(
        kind: QuotaLimitKind,
        remainingPercent: Int,
        resetAt: Date?,
        fetchedAt: Date,
        state: QuotaWindowState
    ) {
        self.kind = kind
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetAt = resetAt
        self.fetchedAt = fetchedAt
        self.state = state
    }
}

// MARK: - Account

/// 登録された1アカウント。
public struct Account: Codable, Identifiable, Equatable, Sendable {
    public enum HomeKind: String, Codable, Sendable {
        /// 既定の Codex ホーム（~/.codex）を参照するアカウント。
        case defaultHome
        /// アプリが管理する個別の CODEX_HOME を持つアカウント。
        case managed
    }

    public var id: UUID
    /// ユーザー設定の表示名。
    public var displayName: String
    public var homeKind: HomeKind
    /// 公式連携側から取得した識別情報（メールアドレス等）。未取得の場合は nil。
    public var officialEmail: String?
    /// 公式連携側から取得したプラン種別。
    public var officialPlanType: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        homeKind: HomeKind,
        officialEmail: String? = nil,
        officialPlanType: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.homeKind = homeKind
        self.officialEmail = officialEmail
        self.officialPlanType = officialPlanType
    }
}

// MARK: - UsageSnapshot

/// 1アカウント分の利用枠スナップショット。
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var accountID: UUID
    public var fiveHour: QuotaWindow?
    public var weekly: QuotaWindow?
    /// 公式から返されたプラン種別（スナップショット取得時点）。
    public var planType: String?
    /// このスナップショットを最後に正常に取得した時刻。
    public var fetchedAt: Date?
    /// 直近の自動取得が失敗した場合のエラー概要（認証情報・秘密URLは含まれない）。
    public var lastErrorMessage: String?
    /// 直近の自動取得が失敗した場合のエラー種別。成功時は nil。
    public var lastErrorKind: UsageErrorKind?

    public init(
        accountID: UUID,
        fiveHour: QuotaWindow? = nil,
        weekly: QuotaWindow? = nil,
        planType: String? = nil,
        fetchedAt: Date? = nil,
        lastErrorMessage: String? = nil,
        lastErrorKind: UsageErrorKind? = nil
    ) {
        self.accountID = accountID
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.planType = planType
        self.fetchedAt = fetchedAt
        self.lastErrorMessage = lastErrorMessage
        self.lastErrorKind = lastErrorKind
    }

    public func window(for kind: QuotaLimitKind) -> QuotaWindow? {
        switch kind {
        case .fiveHour: return fiveHour
        case .weekly: return weekly
        }
    }

    /// スナップショット全体が古くなっているか（最終取得からの経過時間で判定）。
    public func isStale(now: Date = Date(), threshold: TimeInterval = UsageSnapshot.staleThreshold) -> Bool {
        guard let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) > threshold
    }

    /// スナップショットデータがまったく無い状態か。
    public var isEmpty: Bool {
        fiveHour == nil && weekly == nil
    }

    /// stale 判定の閾値（自動更新間隔の数倍を想定した固定値）。
    public static let staleThreshold: TimeInterval = 5 * 60
}

// MARK: - Hot key

/// Carbon の修飾キーフラグ（Events.h の定数値）。
public enum CarbonModifier {
    public static let cmd: Int = 0x0100
    public static let shift: Int = 0x0200
    public static let option: Int = 0x0800
    public static let control: Int = 0x1000
}

/// よく使う仮想キーコード（HIToolbox/Events.h の kVK_ANSI_* 値）。
public enum VirtualKeyCode {
    public static let r = 15
    public static let u = 32
}

/// グローバルショートカット1個分の定義。
/// keyCode はCarbon仮想キーコード、modifiers は `CarbonModifier` の組み合わせ。
public struct HotKeySpec: Codable, Equatable, Hashable, Sendable {
    public var keyCode: Int
    public var modifiers: Int
    /// false なら登録しない（無効化）。
    public var enabled: Bool

    public init(keyCode: Int, modifiers: Int, enabled: Bool = true) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.enabled = enabled
    }

    /// クイック利用状況ウインドウの初期値（Control + Option + U）。
    public static let defaultShowUsage = HotKeySpec(keyCode: VirtualKeyCode.u, modifiers: CarbonModifier.control + CarbonModifier.option)
    /// 手動更新の初期値（Control + Option + R）。
    public static let defaultRefresh = HotKeySpec(keyCode: VirtualKeyCode.r, modifiers: CarbonModifier.control + CarbonModifier.option)

    /// 同じキー＋修飾キーの組み合わせか（enabled は比較しない）。
    public func matches(keyCode: Int, modifiers: Int) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    /// 設定UI向けの表示文字列（例: ⌃⌥U）。未知キーコードは16進表示。
    public var displayText: String {
        modifierSymbols + Self.symbol(forKeyCode: keyCode)
    }

    private var modifierSymbols: String {
        var text = ""
        if modifiers & CarbonModifier.control != 0 { text += "⌃" }
        if modifiers & CarbonModifier.option != 0 { text += "⌥" }
        if modifiers & CarbonModifier.shift != 0 { text += "⇧" }
        if modifiers & CarbonModifier.cmd != 0 { text += "⌘" }
        return text
    }

    /// 仮想キーコード → 表示文字。網羅は不要で、表示できないものは16進で示す。
    static func symbol(forKeyCode keyCode: Int) -> String {
        let table: [Int: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
            12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "W", 13: "Y", 7: "X", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
            28: "8", 25: "9",
            49: "Space", 36: "Return", 53: "Esc", 48: "Tab",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return table[keyCode] ?? String(format: "Key(0x%02X)", keyCode)
    }
}

// MARK: - Usage error kinds

/// 取得エラーの種別。状況別の説明と導線（再試行・再接続・設定）の選択に使う。
public enum UsageErrorKind: String, Codable, CaseIterable, Sendable {
    /// 公式連携側でのログイン（認証）が必要。
    case authenticationRequired
    /// 公式Codex連携（codexバイナリ）が見つからない／起動できない。
    case officialIntegrationMissing
    /// 応答タイムアウト。
    case timeout
    /// 公式連携サーバー側エラー。
    case serverError
    /// 公式連携からの応答形状が不正。
    case invalidResponse
    /// app-server プロセスが終了した。
    case processTerminated
    /// データはあるが古い（取得失敗の継続）— 表示側で付与する。
    case stale
    /// その他。
    case other

    public var titleKey: String { "error.kind.\(rawValue).title" }
    public var explanationKey: String { "error.kind.\(rawValue).explanation" }

    /// エラーから種別を分類する。
    public static func classify(_ error: Error) -> UsageErrorKind {
        switch error {
        case CodexClientError.authenticationRequired:
            return .authenticationRequired
        case CodexClientError.binaryNotFound, CodexClientError.storeHelperMissing, CodexClientError.storeHomeInvalid, CodexClientError.launchFailed:
            return .officialIntegrationMissing
        case CodexClientError.timeout:
            return .timeout
        case CodexClientError.serverError:
            return .serverError
        case CodexClientError.invalidResponse:
            return .invalidResponse
        case CodexClientError.terminated:
            return .processTerminated
        default:
            return .other
        }
    }

    /// エラー状況ごとの導線。UIはこれに対応するボタンを表示する。
    public var recommendedAction: ErrorAction {
        switch self {
        case .authenticationRequired:
            return .openSettings
        case .officialIntegrationMissing:
            return .openSettings
        case .timeout, .serverError, .invalidResponse, .processTerminated:
            return .retry
        case .stale, .other:
            return .retry
        }
    }
}

/// エラー表示に添える導線の種類。
public enum ErrorAction: String, CaseIterable, Sendable {
    /// 今すぐ再試行（手動更新）。
    case retry
    /// 設定を開く（アカウント再接続・公式連携の確認）。
    case openSettings

    public var buttonTitleKey: String { "error.action.\(rawValue)" }
}

// MARK: - AppSettings

/// アプリ全体の設定。
/// デコードはカスタム実装で、旧バージョンの settings.json（新キー欠落）も既定値で読める。
public struct AppSettings: Codable, Equatable, Sendable {
    /// 設定ファイルのスキーマバージョン。項目を追加したら上げる。
    /// v1: 初期リリース / v2: オンボーディング・ショートカット・自動更新確認を追加。
    public static let currentSchemaVersion = 2

    /// この設定ファイルのスキーマバージョン。
    public var schemaVersion: Int
    /// 選択中のアカウントID。
    public var selectedAccountID: UUID?
    /// アカウントごとのメニューバー表示リミット。
    public var displayLimitByAccount: [UUID: QuotaLimitKind]
    /// 通知のオン／オフ（アプリ全体で共通）。
    public var notificationsEnabled: Bool
    /// 低残量通知のしきい値2つ（初期値 20% と 10%）。
    public var notificationThresholds: [Int]
    /// 言語設定（手動上書き）。nil はシステム追従。
    public var languageOverride: AppLanguage?
    /// 自動更新間隔（秒）。
    public var autoRefreshInterval: TimeInterval
    /// ログイン時自動起動。
    public var launchAtLogin: Bool
    /// 初回セットアップ完了済みか。
    public var onboardingCompleted: Bool
    /// 完了した初回セットアップのバージョン（0 = 未実施）。
    public var onboardingVersion: Int
    /// クイック利用状況ウインドウのグローバルショートカット。
    public var showUsageShortcut: HotKeySpec
    /// 手動更新のグローバルショートカット。
    public var refreshShortcut: HotKeySpec
    /// 自動更新確認（1日1回）のオン／オフ。
    public var automaticUpdateChecksEnabled: Bool

    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        selectedAccountID: UUID? = nil,
        displayLimitByAccount: [UUID: QuotaLimitKind] = [:],
        notificationsEnabled: Bool = true,
        notificationThresholds: [Int] = [20, 10],
        languageOverride: AppLanguage? = nil,
        autoRefreshInterval: TimeInterval = 60,
        launchAtLogin: Bool = false,
        onboardingCompleted: Bool = false,
        onboardingVersion: Int = 0,
        showUsageShortcut: HotKeySpec = .defaultShowUsage,
        refreshShortcut: HotKeySpec = .defaultRefresh,
        automaticUpdateChecksEnabled: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.selectedAccountID = selectedAccountID
        self.displayLimitByAccount = displayLimitByAccount
        self.notificationsEnabled = notificationsEnabled
        self.notificationThresholds = notificationThresholds
        self.languageOverride = languageOverride
        self.autoRefreshInterval = autoRefreshInterval
        self.launchAtLogin = launchAtLogin
        self.onboardingCompleted = onboardingCompleted
        self.onboardingVersion = onboardingVersion
        self.showUsageShortcut = showUsageShortcut
        self.refreshShortcut = refreshShortcut
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 旧ファイル（v1）には新キーが無いため、すべての項目を decodeIfPresence で読む
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        selectedAccountID = try container.decodeIfPresent(UUID.self, forKey: .selectedAccountID)
        displayLimitByAccount = try container.decodeIfPresent([UUID: QuotaLimitKind].self, forKey: .displayLimitByAccount) ?? [:]
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notificationThresholds = try container.decodeIfPresent([Int].self, forKey: .notificationThresholds) ?? [20, 10]
        languageOverride = try container.decodeIfPresent(AppLanguage.self, forKey: .languageOverride)
        autoRefreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .autoRefreshInterval) ?? 60
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        onboardingVersion = try container.decodeIfPresent(Int.self, forKey: .onboardingVersion) ?? 0
        showUsageShortcut = try container.decodeIfPresent(HotKeySpec.self, forKey: .showUsageShortcut) ?? .defaultShowUsage
        refreshShortcut = try container.decodeIfPresent(HotKeySpec.self, forKey: .refreshShortcut) ?? .defaultRefresh
        automaticUpdateChecksEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecksEnabled) ?? true
    }

    public func displayLimit(for accountID: UUID) -> QuotaLimitKind {
        displayLimitByAccount[accountID] ?? .fiveHour
    }
}

// MARK: - Language

/// アプリの表示言語。
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case japanese = "ja"
    case english = "en"

    public var localizedNameKey: String {
        switch self {
        case .japanese: return "settings.language.japanese"
        case .english: return "settings.language.english"
        }
    }
}

// MARK: - UsageProvider

/// 利用枠の取得元を表すプロトコル。テストでは MockUsageProvider を使用する。
public protocol UsageProvider: Sendable {
    /// 登録済みアカウントの一覧を返す。
    func accounts() async throws -> [Account]

    /// 指定アカウントの利用枠スナップショットを公式経路から取得する。
    func fetchSnapshot(for account: Account) async throws -> UsageSnapshot

    /// 指定アカウントの公式識別情報を取得する。
    func fetchAccountInfo(for account: Account) async throws -> Account
}
