import Foundation

// MARK: - JSON-RPC types

struct JSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCNotification: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: [String: AnyCodable]?
}

/// AnyEncodable/AnyDecodable 相当の汎用JSON値。
public enum AnyCodable: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case dictionary([String: AnyCodable])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyCodable].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var dictionary: [String: AnyCodable]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }
}

// MARK: - Errors

public enum CodexClientError: Error, LocalizedError, Sendable {
    case binaryNotFound(path: String)
    case launchFailed(String)
    case timeout(method: String)
    case serverError(code: Int, message: String)
    case authenticationRequired
    case terminated
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "Codex CLI not found at \(path). Install the ChatGPT macOS app or Codex CLI."
        case .launchFailed(let reason):
            return "Failed to launch codex app-server: \(reason)"
        case .timeout(let method):
            return "Timed out waiting for response to \(method)"
        case .serverError(let code, let message):
            return "app-server error \(code): \(message)"
        case .authenticationRequired:
            return "codex account authentication required"
        case .terminated:
            return "app-server process terminated"
        case .invalidResponse(let detail):
            return "Unexpected app-server response: \(detail)"
        }
    }
}

// MARK: - Server notification

/// app-server から届いた通知。
public struct ServerNotification: Sendable {
    public let method: String
    public let params: AnyCodable?
}

// MARK: - Client

/// ChatGPT 公式アプリ同梱の Codex CLI (`codex app-server`) と JSON-RPC 2.0 (stdio) で通信するクライアント。
/// 認証情報の読み書きは一切行わない（codex バイナリ自身が CODEX_HOME 配下を管理する）。
public actor CodexAppServerClient {

    /// ChatGPT macOS アプリ同梱の codex バイナリの標準パス。
    public static let bundledBinaryPath = "/Applications/ChatGPT.app/Contents/Resources/codex"

    /// 追加の検索パス（PATH 上の codex も許容する）。
    public static let fallbackBinaryNames = ["codex"]

    private let executableURL: URL
    private let codexHome: URL?
    private let clientName: String
    private let clientVersion: String

    private var process: Process?
    private var stdin: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<AnyCodable, Error>] = [:]
    private var notificationContinuations: [UUID: AsyncStream<ServerNotification>.Continuation] = [:]
    private var readBuffer = Data()
    private let encoder = JSONEncoder()
    private let logger = AppLogger(category: "CodexAppServerClient")
    private var initialized = false

    /// - Parameters:
    ///   - codexHome: このクライアントが対象とする CODEX_HOME。nil の場合は既定 (~/.codex)。
    public init(
        executableURL: URL? = nil,
        codexHome: URL? = nil,
        clientName: String = "AI Usage Buddy",
        clientVersion: String = "1.0.0"
    ) {
        if let executableURL {
            self.executableURL = executableURL
        } else if FileManager.default.fileExists(atPath: Self.bundledBinaryPath) {
            self.executableURL = URL(fileURLWithPath: Self.bundledBinaryPath)
        } else {
            self.executableURL = URL(fileURLWithPath: "codex")
        }
        self.codexHome = codexHome
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    public func isAlive() -> Bool {
        process?.isRunning ?? false
    }

    /// プロセスを起動し initialize ハンドシェイクを行う。
    public func start() async throws {
        guard process?.isRunning != true else { return }

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        if let codexHome {
            environment["CODEX_HOME"] = codexHome.path
        }
        proc.environment = environment
        proc.standardError = Pipe()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe

        do {
            try proc.run()
        } catch {
            throw CodexClientError.launchFailed(error.localizedDescription)
        }

        self.process = proc
        self.stdin = stdinPipe.fileHandleForWriting
        self.initialized = false

        // プロセス終了を監視し、待機中のリクエストを失敗させる
        Task.detached { [weak self] in
            proc.waitUntilExit()
            await self?.handleTermination(status: proc.terminationStatus)
        }

        // stdout の行読み取り
        Task.detached { [weak self] in
            await self?.readLines(from: stdoutPipe.fileHandleForReading)
        }

        // initialize ハンドシェイク
        _ = try await request(
            method: "initialize",
            params: [
                "clientInfo": .dictionary([
                    "name": .string(self.clientName),
                    "version": .string(self.clientVersion),
                ])
            ]
        )
        sendNotification(method: "initialized", params: [:])
        initialized = true
    }

    /// プロセスを終了する。
    public func stop() {
        for continuation in pending.values {
            continuation.resume(throwing: CodexClientError.terminated)
        }
        pending.removeAll()
        for cont in notificationContinuations.values {
            cont.finish()
        }
        notificationContinuations.removeAll()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdin = nil
        initialized = false
    }

    // MARK: - 公式メソッド

    /// `account/read` — アカウント識別情報（email, planType）を取得する。
    public func readAccount() async throws -> GetAccountResponse {
        let result = try await request(method: "account/read", params: [:])
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(GetAccountResponse.self, from: data)
    }

    /// `account/rateLimits/read` — 5時間枠・週間枠の残量とリセット時刻を取得する。
    public func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        let result = try await request(method: "account/rateLimits/read", params: [:])
        let data = try JSONEncoder().encode(result)
        do {
            return try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: data)
        } catch {
            // 認証エラーは JSON-RPC エラーとして届くが、結果形状が異なる場合の保険
            throw CodexClientError.invalidResponse(String(describing: error))
        }
    }

    /// `account/login/start` — 公式 OAuth ログインを開始し authUrl を得る。
    public func startLogin() async throws -> LoginStartResult {
        let result = try await request(
            method: "account/login/start",
            params: ["type": .string("chatgpt")]
        )
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(LoginStartResult.self, from: data)
    }

    /// `account/logout` — この CODEX_HOME のログインを解除する（アカウント削除時に使用）。
    public func logout() async throws {
        _ = try await request(method: "account/logout", params: [:])
    }

    /// サーバ通知のストリーム（account/login/completed や account/rateLimits/updated 等）。
    public func notifications() -> AsyncStream<ServerNotification> {
        AsyncStream { continuation in
            let id = UUID()
            notificationContinuations[id] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeNotificationContinuation(id: id) }
            }
        }
    }

    private func removeNotificationContinuation(id: UUID) {
        notificationContinuations[id] = nil
    }

    // MARK: - Transport

    private func request(method: String, params: [String: AnyCodable], timeout: TimeInterval = 25) async throws -> AnyCodable {
        guard let stdin else { throw CodexClientError.terminated }
        let id = nextID
        nextID += 1

        let rpc = JSONRPCRequest(id: id, method: method, params: params)
        let body: Data
        do {
            body = try encoder.encode(rpc)
        } catch {
            throw CodexClientError.invalidResponse("failed to encode request \(method)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            // タイムアウト管理
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.failPending(id: id, error: CodexClientError.timeout(method: method))
            }

            pending[id] = continuation
            pendingTaskTimeouts[id] = timeoutTask

            stdin.write(body + Data("\n".utf8))
        }
    }

    private var pendingTaskTimeouts: [Int: Task<Void, Never>] = [:]

    private func failPending(id: Int, error: Error) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        pendingTaskTimeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(throwing: error)
    }

    private func sendNotification(method: String, params: [String: AnyCodable]) {
        guard let stdin else { return }
        let rpc = JSONRPCNotification(method: method, params: params)
        guard let data = try? encoder.encode(rpc) else { return }
        stdin.write(data + Data("\n".utf8))
    }

    private func handleTermination(status: Int32) {
        for continuation in pending.values {
            continuation.resume(throwing: CodexClientError.terminated)
        }
        pending.removeAll()
        for cont in notificationContinuations.values {
            cont.finish()
        }
        notificationContinuations.removeAll()
        process = nil
        stdin = nil
        initialized = false
        if status != 0 {
            logger.error("app-server exited with status \(status)")
        }
    }

    /// stdout を行単位で読み取り JSON-RPC メッセージを振り分ける。
    private func readLines(from handle: FileHandle) async {
        let chunks = AsyncStream<Data> { continuation in
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                if data.isEmpty {
                    fh.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }

        for await chunk in chunks {
            readBuffer.append(chunk)
            while let lineEndIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = readBuffer[readBuffer.startIndex..<lineEndIndex]
                readBuffer.removeSubrange(readBuffer.startIndex...lineEndIndex)
                guard !lineData.isEmpty else { continue }
                do {
                    let message = try JSONDecoder().decode(JSONRPCIncomingMessage.self, from: Data(lineData))
                    await route(message: message)
                } catch {
                    logger.debug("ignoring non-JSON line from app-server")
                }
            }
        }
    }

    private func route(message: JSONRPCIncomingMessage) async {
        if let id = message.id {
            // レスポンス
            if let error = message.error {
                let code = (error["code"]?.intValue) ?? -1
                let messageText = error["message"]?.stringValue ?? "unknown error"
                failPending(id: id, error: CodexClientError.serverError(code: code, message: messageText))
            } else if let result = message.result {
                guard let continuation = pending.removeValue(forKey: id) else { return }
                pendingTaskTimeouts.removeValue(forKey: id)?.cancel()
                continuation.resume(returning: result)
            }
        } else if let method = message.method {
            // サーバ通知
            let params = message.params.map { AnyCodable.dictionary($0) }
            let notification = ServerNotification(method: method, params: params)
            for cont in notificationContinuations.values {
                cont.yield(notification)
            }
        }
    }
}

// MARK: - Incoming message envelope

struct JSONRPCIncomingMessage: Decodable {
    let id: Int?
    let result: AnyCodable?
    let error: [String: AnyCodable]?
    let method: String?
    let params: [String: AnyCodable]?
}

// MARK: - Response models (official app-server protocol v2 schema)

/// `account/read` のレスポンス。
public struct GetAccountResponse: Decodable, Sendable {
    public struct AccountInfo: Decodable, Sendable {
        public let type: String
        public let email: String?
        public let planType: String?
    }

    public let account: AccountInfo?
    public let requiresOpenaiAuth: Bool
}

/// `account/login/start` のレスポンス。
public struct LoginStartResult: Decodable, Sendable {
    public let type: String?
    public let authUrl: String?
    public let loginId: String?
}
