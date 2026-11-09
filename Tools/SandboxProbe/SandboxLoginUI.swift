import AppKit
import Darwin
import Foundation

func sandboxProbeLoginActionEnabled(sessionAvailable: Bool, loginPending: Bool, busy: Bool) -> Bool {
    sessionAvailable && !loginPending && !busy
}

enum SandboxProbeDiagnosticStage: String {
    case loginStart = "login_start"
    case loopbackListener = "loopback_listener"
}

enum SandboxProbeDiagnosticCode: String {
    case loginStartRPCError = "login_start_rpc_error"
    case loginStartAuthenticationRequired = "login_start_authentication_required"
    case loginStartTimeout = "login_start_timeout"
    case loginStartClosed = "login_start_closed"
    case loginStartInvalidRPCResponse = "login_start_invalid_rpc_response"
    case loginStartInvalidResultSchema = "login_start_invalid_result_schema"
    case loginStartInvalidAuthURL = "login_start_invalid_auth_url"
    case loopbackListenPassed = "loopback_listen_passed"
    case loopbackSocketPermissionDenied = "loopback_socket_permission_denied"
    case loopbackSocketFailed = "loopback_socket_failed"
    case loopbackBindPermissionDenied = "loopback_bind_permission_denied"
    case loopbackBindAddressInUse = "loopback_bind_address_in_use"
    case loopbackBindFailed = "loopback_bind_failed"
    case loopbackListenPermissionDenied = "loopback_listen_permission_denied"
    case loopbackListenFailed = "loopback_listen_failed"
}

@discardableResult
func recordSandboxProbeDiagnostic(
    stage: SandboxProbeDiagnosticStage,
    code: SandboxProbeDiagnosticCode,
    diagnosticID: UUID = UUID(),
    systemCode: Int? = nil
) -> Bool {
    let bundleID = "com.aiusagebuddy.app.sandboxprobe"
    let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
    guard Bundle.main.bundleIdentifier == bundleID,
          home.path.hasSuffix("/Library/Containers/\(bundleID)/Data") else { return false }

    let directory = home.appendingPathComponent(
        "Library/Application Support/AIUsageBuddySandboxProbe/Diagnostics",
        isDirectory: true
    )
    do {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var report: [String: Any] = [
            "schemaVersion": 1,
            "diagnosticID": diagnosticID.uuidString.lowercased(),
            "stage": stage.rawValue,
            "code": code.rawValue
        ]
        if let systemCode { report["systemCode"] = systemCode }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let reportURL = directory.appendingPathComponent("probe-\(diagnosticID.uuidString.lowercased()).json")
        try data.write(to: reportURL, options: .atomic)
        return true
    } catch {
        return false
    }
}

@MainActor
enum SandboxLoginUI {
    private static let expectedBundleID = "com.aiusagebuddy.app.sandboxprobe"
    private static let containerSuffix = "/Library/Containers/\(expectedBundleID)/Data"

    static func makeController() -> SandboxLoginWindowController {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        guard Bundle.main.bundleIdentifier == expectedBundleID,
              home.path.hasSuffix(containerSuffix) else {
            return SandboxLoginWindowController(
                session: nil,
                initialStatus: "Sandbox containerを確認できません。通常のHOMEには接続しません。"
            )
        }

        let persistentRoot = home
            .appendingPathComponent("Library/Application Support/AIUsageBuddySandboxProbe/Persistent", isDirectory: true)
        let accountARoot = persistentRoot.appendingPathComponent("Account-A", isDirectory: true)
        let accountBRoot = persistentRoot.appendingPathComponent("Account-B", isDirectory: true)
        let accountHome = accountARoot.appendingPathComponent("CODEX_HOME", isDirectory: true)
        let workingDirectory = accountARoot.appendingPathComponent("Working", isDirectory: true)
        let temporaryDirectory = accountARoot.appendingPathComponent("Temporary", isDirectory: true)

        do {
            for directory in [
                accountHome,
                workingDirectory,
                temporaryDirectory,
                accountBRoot.appendingPathComponent("CODEX_HOME", isDirectory: true)
            ] {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        } catch {
            return SandboxLoginWindowController(
                session: nil,
                initialStatus: "Sandbox専用領域を準備できません。通常のHOMEには接続しません。"
            )
        }

        let session = SandboxAppServerSession(
            executable: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            home: accountHome,
            workingDirectory: workingDirectory,
            temporaryDirectory: temporaryDirectory
        )
        return SandboxLoginWindowController(
            session: session,
            initialStatus: "検証専用のAccount-A領域です。既存アプリの設定・ログイン状態には触れません。"
        )
    }
}

@MainActor
final class SandboxLoginWindowController: NSObject, NSWindowDelegate {
    private let session: SandboxAppServerSession?
    private let window: NSWindow
    private let statusLabel: NSTextField
    private let loginButton = NSButton(title: "検証用アカウントでログイン", target: nil, action: nil)
    private let limitsButton = NSButton(title: "残量を確認", target: nil, action: nil)
    private let exitButton = NSButton(title: "終了", target: nil, action: nil)
    private let cancelButton = NSButton(title: "ログインをキャンセル", target: nil, action: nil)
    private var terminationInProgress = false
    private var terminationFinished = false

    fileprivate init(session: SandboxAppServerSession?, initialStatus: String) {
        self.session = session
        self.statusLabel = NSTextField(wrappingLabelWithString: initialStatus)
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "AI Usage Buddy — Sandbox Probe"
        window.delegate = self
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping

        let loginRow = NSStackView(views: [loginButton, cancelButton])
        loginRow.orientation = .horizontal
        loginRow.distribution = .fillEqually
        loginRow.spacing = 10

        let actionRow = NSStackView(views: [limitsButton, exitButton])
        actionRow.orientation = .horizontal
        actionRow.distribution = .fillEqually
        actionRow.spacing = 10

        let actions = NSStackView(views: [loginRow, actionRow])
        actions.orientation = .vertical
        actions.distribution = .fillEqually
        actions.spacing = 10

        let content = NSStackView(views: [statusLabel, actions])
        content.orientation = .vertical
        content.alignment = .leading
        content.distribution = .fill
        content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            actions.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
        window.contentView = container

        loginButton.target = self
        loginButton.action = #selector(beginLogin)
        limitsButton.target = self
        limitsButton.action = #selector(readLimits)
        exitButton.target = self
        exitButton.action = #selector(exitProbe)
        cancelButton.target = self
        cancelButton.action = #selector(cancelLogin)
        cancelButton.isHidden = true
        limitsButton.isEnabled = session != nil
        loginButton.isEnabled = session != nil
        window.center()

        session?.onStatus = { [weak self] message, loginPending, busy in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusLabel.stringValue = message
                self.cancelButton.isHidden = !loginPending
                self.cancelButton.isEnabled = !busy
                self.loginButton.isEnabled = sandboxProbeLoginActionEnabled(
                    sessionAvailable: self.session != nil,
                    loginPending: loginPending,
                    busy: busy
                )
                self.limitsButton.isEnabled = self.session != nil && !loginPending && !busy
            }
        }
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func prepareToTerminate() -> NSApplication.TerminateReply {
        if terminationFinished { return .terminateNow }
        guard !terminationInProgress else { return .terminateCancel }
        terminationInProgress = true
        guard let session else {
            terminationFinished = true
            return .terminateNow
        }
        session.shutdown { [weak self] cleanedUp in
            guard let self else { return }
            self.terminationInProgress = false
            if cleanedUp {
                self.terminationFinished = true
                NSApp.terminate(nil)
            } else {
                self.statusLabel.stringValue = "子プロセスの終了を確認できませんでした。ウィンドウを閉じて再試行してください。"
            }
        }
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    @objc private func beginLogin() {
        loginButton.isEnabled = false
        limitsButton.isEnabled = false
        statusLabel.stringValue = "ログイン開始を準備しています。ブラウザはボタン操作後に開きます。"
        session?.startLogin()
    }

    @objc private func readLimits() {
        loginButton.isEnabled = false
        limitsButton.isEnabled = false
        statusLabel.stringValue = "Account-Aの状態を確認しています。"
        session?.readLimits()
    }

    @objc private func cancelLogin() {
        session?.cancelLogin()
    }

    @objc private func exitProbe() {
        NSApp.terminate(nil)
    }
}

enum LoginRPCReply {
    case result([String: Any])
    case rpcError(authenticationRequired: Bool)
    case timeout
    case closed
    case invalid
}

func sandboxProbeLoginCancelConfirmed(_ reply: LoginRPCReply) -> Bool {
    if case .result = reply { return true }
    return false
}

func sandboxProbeLoginStartFailureCode(_ reply: LoginRPCReply) -> SandboxProbeDiagnosticCode? {
    switch reply {
    case .rpcError(let authenticationRequired):
        return authenticationRequired ? .loginStartAuthenticationRequired : .loginStartRPCError
    case .timeout:
        return .loginStartTimeout
    case .closed:
        return .loginStartClosed
    case .invalid:
        return .loginStartInvalidRPCResponse
    case .result:
        return nil
    }
}

func sandboxProbeLoginStartPayloadFailureCode(loginID: String?, authURLText: String?) -> SandboxProbeDiagnosticCode? {
    guard let loginID, !loginID.isEmpty, let authURLText, !authURLText.isEmpty else {
        return .loginStartInvalidResultSchema
    }
    guard let url = URL(string: authURLText),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme?.lowercased() == "https",
          components.host?.isEmpty == false,
          components.user == nil,
          components.password == nil else {
        return .loginStartInvalidAuthURL
    }
    return nil
}

private final class SandboxAppServerSession {
    private struct PendingRequest {
        let completion: (LoginRPCReply) -> Void
        let timeout: DispatchWorkItem
    }

    private let queue = DispatchQueue(label: "com.aiusagebuddy.sandboxprobe.appserver")
    private let executable: String
    private let home: URL
    private let workingDirectory: URL
    private let temporaryDirectory: URL
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var readSource: DispatchSourceRead?
    private var outputBuffer = Data()
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var initialized = false
    private var initializationInFlight = false
    private var initializationWaiters: [(Bool) -> Void] = []
    private var activeLoginID: String?
    private var loginTimeout: DispatchWorkItem?
    private var shuttingDown = false
    private var shutdownFinished = false
    private var shutdownCompletion: ((Bool) -> Void)?

    var onStatus: ((String, Bool, Bool) -> Void)?

    init(executable: String, home: URL, workingDirectory: URL, temporaryDirectory: URL) {
        self.executable = executable
        self.home = home
        self.workingDirectory = workingDirectory
        self.temporaryDirectory = temporaryDirectory
    }

    func startLogin() {
        queue.async {
            guard !self.shuttingDown else { return }
            self.publish("app-serverを準備しています。", loginPending: false, busy: true)
            self.ensureInitialized { ready in
                guard ready else {
                    self.publish("Codex app-serverを起動できませんでした。", loginPending: false)
                    return
                }
                self.sendRequest(method: "account/login/start", params: [
                    "type": "chatgpt"
                ], timeoutSeconds: 15) { reply in
                    guard case .result(let result) = reply else {
                        self.failLoginStart(with: sandboxProbeLoginStartFailureCode(reply) ?? .loginStartInvalidRPCResponse)
                        return
                    }
                    guard let loginID = result["loginId"] as? String,
                          let authURLText = result["authUrl"] as? String else {
                        self.failLoginStart(with: .loginStartInvalidResultSchema)
                        return
                    }
                    if let failure = sandboxProbeLoginStartPayloadFailureCode(
                        loginID: loginID,
                        authURLText: authURLText
                    ) {
                        self.failLoginStart(with: failure)
                        return
                    }
                    guard let authURL = URL(string: authURLText) else {
                        self.failLoginStart(with: .loginStartInvalidAuthURL)
                        return
                    }
                    self.activeLoginID = loginID
                    self.publish("ブラウザでログインしてください。完了しない場合は5分以内にキャンセルできます。", loginPending: true)
                    let timeout = DispatchWorkItem { [weak self] in
                        self?.cancelLoginOnQueue(status: "待機期限後のログインキャンセルを確認しました。再試行できます。")
                    }
                    self.loginTimeout = timeout
                    self.queue.asyncAfter(deadline: .now() + 300, execute: timeout)
                    DispatchQueue.main.async {
                        let opened = NSWorkspace.shared.open(authURL)
                        if !opened {
                            self.queue.async {
                                self.cancelLoginOnQueue(status: "ブラウザ起動失敗後のログインキャンセルを確認しました。")
                            }
                        }
                    }
                }
            }
        }
    }

    func readLimits() {
        queue.async {
            guard !self.shuttingDown else { return }
            self.publish("Account-Aの状態を確認しています。", loginPending: false, busy: true)
            self.ensureInitialized { ready in
                guard ready else {
                    self.publish("Codex app-serverを起動できませんでした。", loginPending: false)
                    return
                }
                self.sendRequest(method: "account/read", params: [:], timeoutSeconds: 10) { reply in
                    guard case .result(let accountResult) = reply else {
                        self.publish(self.safeReadFailure(reply), loginPending: false)
                        return
                    }
                    let account = accountResult["account"] as? [String: Any]
                    let accountType = account?["type"] as? String
                    if (accountType?.isEmpty ?? true), accountResult["requiresOpenaiAuth"] as? Bool == true {
                        self.publish("Account-Aは未ログインです。ログインボタンから検証できます。", loginPending: false)
                        return
                    }
                    self.sendRequest(method: "account/rateLimits/read", params: [:], timeoutSeconds: 10) { limitsReply in
                        guard case .result(let result) = limitsReply else {
                            self.publish(self.safeReadFailure(limitsReply), loginPending: false)
                            return
                        }
                        self.publish(Self.safeLimitSummary(result), loginPending: false)
                    }
                }
            }
        }
    }

    func cancelLogin() {
        queue.async {
            self.cancelLoginOnQueue(status: "ログインキャンセルを確認しました。再試行できます。")
        }
    }

    func shutdown(completion: @escaping (Bool) -> Void) {
        queue.async {
            if self.shutdownFinished {
                DispatchQueue.main.async { completion(true) }
                return
            }
            self.shutdownCompletion = completion
            self.shuttingDown = true
            self.loginTimeout?.cancel()
            if let loginID = self.activeLoginID, self.process?.isRunning == true {
                self.activeLoginID = nil
                self.sendRequest(
                    method: "account/login/cancel",
                    params: ["loginId": loginID],
                    timeoutSeconds: 1
                ) { _ in self.finishShutdownOnQueue() }
                self.queue.asyncAfter(deadline: .now() + 1.2) {
                    self.finishShutdownOnQueue()
                }
            } else {
                self.finishShutdownOnQueue()
            }
        }
    }

    private func ensureInitialized(_ completion: @escaping (Bool) -> Void) {
        if initialized {
            completion(true)
            return
        }
        initializationWaiters.append(completion)
        guard !initializationInFlight else { return }
        initializationInFlight = true

        let child = Process()
        let input = Pipe()
        let output = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = ["app-server"]
        child.currentDirectoryURL = workingDirectory
        child.environment = [
            "HOME": home.path,
            "CODEX_HOME": home.path,
            "TMPDIR": temporaryDirectory.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
        } catch {
            completeInitialization(false)
            return
        }

        process = child
        inputPipe = input
        outputPipe = output
        let descriptor = output.fileHandleForReading.fileDescriptor
        let currentFlags = fcntl(descriptor, F_GETFL)
        if currentFlags >= 0 {
            _ = fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        readSource = source
        source.resume()

        sendRequest(method: "initialize", params: [
            "clientInfo": ["name": "AIUsageBuddy Sandbox Probe", "version": "0.1.0"]
        ], timeoutSeconds: 10) { reply in
            if sandboxProbeLoginCancelConfirmed(reply) {
                self.sendNotification(method: "initialized", params: [:])
                self.initialized = true
                self.completeInitialization(true)
            } else {
                self.completeInitialization(false)
            }
        }
    }

    private func completeInitialization(_ success: Bool) {
        initializationInFlight = false
        let waiters = initializationWaiters
        initializationWaiters.removeAll()
        waiters.forEach { $0(success) }
    }

    private func sendRequest(
        method: String,
        params: [String: Any],
        timeoutSeconds: Int,
        completion: @escaping (LoginRPCReply) -> Void
    ) {
        guard let input = inputPipe?.fileHandleForWriting,
              let body = try? JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "id": nextRequestID,
                "method": method,
                "params": params
              ], options: [.sortedKeys]) else {
            completion(.invalid)
            return
        }
        let requestID = nextRequestID
        nextRequestID += 1
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let request = self.pending.removeValue(forKey: requestID) else { return }
            request.timeout.cancel()
            request.completion(.timeout)
        }
        pending[requestID] = PendingRequest(completion: completion, timeout: timeout)
        queue.asyncAfter(deadline: .now() + .seconds(timeoutSeconds), execute: timeout)
        do {
            try input.write(contentsOf: body + Data([0x0A]))
        } catch {
            completeRequest(requestID, reply: .closed)
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        guard let input = inputPipe?.fileHandleForWriting,
              let body = try? JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "method": method,
                "params": params
              ], options: [.sortedKeys]) else { return }
        try? input.write(contentsOf: body + Data([0x0A]))
    }

    private func readAvailable() {
        guard let descriptor = outputPipe?.fileHandleForReading.fileDescriptor else { return }
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                outputBuffer.append(contentsOf: bytes.prefix(count))
                guard outputBuffer.count <= 1_048_576 else {
                    failPendingRequests()
                    return
                }
                while let newline = outputBuffer.firstIndex(of: 0x0A) {
                    let line = Data(outputBuffer[..<newline])
                    outputBuffer.removeSubrange(outputBuffer.startIndex...newline)
                    handleMessage(line)
                }
                continue
            }
            if count == 0 {
                failPendingRequests()
                return
            }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            failPendingRequests()
            return
        }
    }

    private func handleMessage(_ line: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if message["method"] as? String == "account/login/completed",
           let params = message["params"] as? [String: Any],
           let loginID = params["loginId"] as? String,
           loginID == activeLoginID {
            loginTimeout?.cancel()
            loginTimeout = nil
            activeLoginID = nil
            publish(
                params["success"] as? Bool == true
                    ? "ログインが完了しました。必要なら「残量を確認」を押してください。"
                    : "ログインが完了しませんでした。再試行できます。",
                loginPending: false
            )
            return
        }
        guard let requestID = message["id"] as? Int else { return }
        if let error = message["error"] as? [String: Any] {
            let messageText = (error["message"] as? String ?? "").lowercased()
            completeRequest(
                requestID,
                reply: .rpcError(authenticationRequired: messageText.contains("authentication required"))
            )
        } else if let result = message["result"] as? [String: Any] {
            completeRequest(requestID, reply: .result(result))
        } else {
            completeRequest(requestID, reply: .invalid)
        }
    }

    private func completeRequest(_ requestID: Int, reply: LoginRPCReply) {
        guard let request = pending.removeValue(forKey: requestID) else { return }
        request.timeout.cancel()
        request.completion(reply)
    }

    private func failLoginStart(with code: SandboxProbeDiagnosticCode) {
        recordSandboxProbeDiagnostic(stage: .loginStart, code: code)
        publish("ログイン開始に失敗しました（診断コード: \(code.rawValue)）。生の応答は表示・保存しません。", loginPending: false)
    }

    private func failPendingRequests() {
        let requests = pending
        pending.removeAll()
        requests.values.forEach {
            $0.timeout.cancel()
            $0.completion(.closed)
        }
        if initializationInFlight { completeInitialization(false) }
    }

    private func cancelLoginOnQueue(status: String) {
        guard let loginID = activeLoginID else { return }
        loginTimeout?.cancel()
        loginTimeout = nil
        publish("ログインキャンセル応答を確認しています。", loginPending: true, busy: true)
        sendRequest(method: "account/login/cancel", params: ["loginId": loginID], timeoutSeconds: 3) { reply in
            guard self.activeLoginID == loginID else { return }
            if case .result = reply {
                self.activeLoginID = nil
                self.publish(status, loginPending: false)
            } else {
                self.publish(
                    "キャンセルは未確認です。再試行するか「終了」で専用app-serverを停止してください。",
                    loginPending: true
                )
            }
        }
    }

    private func safeReadFailure(_ reply: LoginRPCReply) -> String {
        switch reply {
        case .rpcError(let authenticationRequired):
            return authenticationRequired ? "認証が必要です。ログイン状態を確認してください。" : "読み取りRPCに失敗しました。"
        case .timeout: return "読み取りRPCがタイムアウトしました。"
        case .closed: return "Codex app-serverが終了しました。"
        case .invalid: return "RPC応答を確認できませんでした。"
        case .result: return ""
        }
    }

    private static func safeLimitSummary(_ result: [String: Any]) -> String {
        guard let limits = result["rateLimits"] as? [String: Any] else {
            return "残量応答を受信しましたが、表示できる枠がありません。"
        }
        var summaries: [String] = []
        for (key, title) in [("primary", "5時間枠"), ("secondary", "週間枠")] {
            guard let window = limits[key] as? [String: Any],
                  let used = window["usedPercent"] as? Int else { continue }
            summaries.append("\(title) 残り \(max(0, min(100, 100 - used)))%")
        }
        return summaries.isEmpty
            ? "残量応答を受信しましたが、表示できる枠がありません。"
            : summaries.joined(separator: "　")
    }

    private func publish(_ message: String, loginPending: Bool, busy: Bool = false) {
        guard let onStatus else { return }
        DispatchQueue.main.async { onStatus(message, loginPending, busy) }
    }

    private func finishShutdownOnQueue() {
        guard !shutdownFinished else { return }
        loginTimeout?.cancel()
        failPendingRequests()

        if let process, process.isRunning {
            process.terminate()
            let terminateDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < terminateDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                let pid = process.processIdentifier
                let killResult = Darwin.kill(pid, SIGKILL)
                let killDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    shuttingDown = false
                    let completion = shutdownCompletion
                    shutdownCompletion = nil
                    publish("子プロセス終了未確認 (PID \(pid), kill結果 \(killResult))。終了を再試行してください。", loginPending: false)
                    if let completion { DispatchQueue.main.async { completion(false) } }
                    return
                }
                process.waitUntilExit()
            } else {
                process.waitUntilExit()
            }
        }

        readSource?.cancel()
        readSource = nil
        try? inputPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close()
        shutdownFinished = true
        let completion = shutdownCompletion
        shutdownCompletion = nil
        if let completion { DispatchQueue.main.async { completion(true) } }
    }
}
