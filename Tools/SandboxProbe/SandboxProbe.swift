import AppKit
import Darwin
import Foundation

private let expectedBundleID = "com.aiusagebuddy.app.sandboxprobe"
private let containerSuffix = "/Library/Containers/\(expectedBundleID)/Data"

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var loginWindowController: SandboxLoginWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            let passed = SandboxProbeSelfTest.run()
            FileHandle.standardOutput.write(Data((passed ? "sandbox-probe-self-test: passed\n" : "sandbox-probe-self-test: failed\n").utf8))
            Darwin.exit(passed ? 0 : 1)
        }
        if CommandLine.arguments.contains("--listener-self-test") {
            let arguments = CommandLine.arguments
            guard let idText = argument("--diagnostic-id", in: arguments),
                  let diagnosticID = UUID(uuidString: idText),
                  diagnosticID.uuidString.lowercased() == idText.lowercased() else {
                Darwin.exit(2)
            }
            let result = loopbackListenerSelfTest()
            let recorded = recordSandboxProbeDiagnostic(
                stage: .loopbackListener,
                code: result.code,
                diagnosticID: diagnosticID,
                systemCode: result.systemCode
            )
            Darwin.exit(recorded && result.code == .loopbackListenPassed ? 0 : 1)
        }
        if CommandLine.arguments.contains("--login") {
            loginWindowController = SandboxLoginUI.makeController()
            loginWindowController?.showWindow()
            return
        }
        runProbe()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard CommandLine.arguments.contains("--login") else { return .terminateNow }
        return loginWindowController?.prepareToTerminate() ?? .terminateNow
    }

    private func runProbe() {
        let arguments = CommandLine.arguments
        guard let runID = argument("--run-id", in: arguments),
              let uuid = UUID(uuidString: runID),
              uuid.uuidString.lowercased() == runID.lowercased(),
              let codexPath = argument("--codex-binary", in: arguments),
              let fixturePath = argument("--fixture", in: arguments) else {
            return
        }

        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        let homeIsContainer = home.path.hasSuffix(containerSuffix)
        // Never fall back to the user's ordinary home or write there if the app
        // was not launched with its expected App Sandbox container.
        guard homeIsContainer,
              Bundle.main.bundleIdentifier == expectedBundleID else {
            return
        }

        let runRoot = home
            .appendingPathComponent("Library/Application Support/AIUsageBuddySandboxProbe/Runs", isDirectory: true)
            .appendingPathComponent(uuid.uuidString.lowercased(), isDirectory: true)
        let accountARoot = runRoot.appendingPathComponent("Account-A", isDirectory: true)
        let accountHome = accountARoot.appendingPathComponent("CODEX_HOME", isDirectory: true)
        let workingDirectory = accountARoot.appendingPathComponent("Working", isDirectory: true)
        let temporaryDirectory = accountARoot.appendingPathComponent("Temporary", isDirectory: true)
        let reportURL = runRoot.appendingPathComponent("Report.json")

        do {
            for directory in [runRoot, accountARoot, accountHome, workingDirectory, temporaryDirectory] {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        } catch {
            writeReport([
                "schemaVersion": 1,
                "runId": uuid.uuidString.lowercased(),
                "bundleIdMatches": true,
                "homeIsSandboxContainer": true,
                "setupStatus": "container_setup_failed"
            ], to: reportURL)
            return
        }

        let fixtureStatus = checkFixture(at: fixturePath)
        let versionResult = runVersion(
            executable: codexPath,
            home: accountHome,
            workingDirectory: workingDirectory,
            temporaryDirectory: temporaryDirectory
        )

        let accountBRoot = runRoot.appendingPathComponent("Account-B", isDirectory: true)
        let accountBHome = accountBRoot.appendingPathComponent("CODEX_HOME", isDirectory: true)
        let accountBWorkingDirectory = accountBRoot.appendingPathComponent("Working", isDirectory: true)
        let accountBTemporaryDirectory = accountBRoot.appendingPathComponent("Temporary", isDirectory: true)
        var rpcPhase = "skipped_version_failed"
        var accountAResult: RPCSummary?
        var accountBResult: RPCSummary?
        if versionResult.status == "passed" {
            do {
                for directory in [accountBRoot, accountBHome, accountBWorkingDirectory, accountBTemporaryDirectory] {
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                }
                rpcPhase = "completed"
                accountAResult = runReadOnlyRPC(
                    executable: codexPath,
                    home: accountHome,
                    workingDirectory: workingDirectory,
                    temporaryDirectory: temporaryDirectory
                )
                accountBResult = runReadOnlyRPC(
                    executable: codexPath,
                    home: accountBHome,
                    workingDirectory: accountBWorkingDirectory,
                    temporaryDirectory: accountBTemporaryDirectory
                )
            } catch {
                rpcPhase = "container_setup_failed"
            }
        }

        var report: [String: Any] = [
            "schemaVersion": 1,
            "runId": uuid.uuidString.lowercased(),
            "bundleIdMatches": Bundle.main.bundleIdentifier == expectedBundleID,
            "homeIsSandboxContainer": homeIsContainer,
            "codexHomeIsInContainer": isDescendant(accountHome, of: home),
            "workingDirectoryIsInContainer": isDescendant(workingDirectory, of: home),
            "externalFixtureAccess": fixtureStatus.category,
            "externalFixtureErrorClass": fixtureStatus.errorClass,
            "versionCheckScope": "codex --version only",
            "codexVersionPhase": versionResult.status,
            "versionExitCode": versionResult.exitCode as Any? ?? NSNull(),
            "versionSignal": versionResult.signal as Any? ?? NSNull(),
            "versionSpawnErrorDomain": versionResult.errorDomain as Any? ?? NSNull(),
            "versionSpawnErrorCode": versionResult.errorCode as Any? ?? NSNull(),
            "versionTimedOut": versionResult.timedOut,
            "processCleanup": versionResult.cleanup,
            "versionCleanupPID": versionResult.cleanupPID as Any? ?? NSNull(),
            "versionKillResult": versionResult.killResult as Any? ?? NSNull(),
            "versionKillErrno": versionResult.killErrno as Any? ?? NSNull()
        ]
        report["rpcPhase"] = rpcPhase
        report["rpcHomesDistinct"] = accountHome.standardizedFileURL != accountBHome.standardizedFileURL
        report["accountA"] = accountAResult?.jsonObject ?? NSNull()
        report["accountB"] = accountBResult?.jsonObject ?? NSNull()
        writeReport(report, to: reportURL)
    }

    private func argument(_ key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private func checkFixture(at path: String) -> (category: String, errorClass: String) {
        let descriptor = path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        guard descriptor >= 0 else {
            switch errno {
            case EACCES: return ("denied", "eacces")
            case EPERM: return ("denied", "eperm")
            case ENOENT: return ("not_found", "enoent")
            default: return ("error", "other")
            }
        }
        Darwin.close(descriptor)
        return ("accessible", "none")
    }

    private func runVersion(
        executable: String,
        home: URL,
        workingDirectory: URL,
        temporaryDirectory: URL
    ) -> VersionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        process.currentDirectoryURL = workingDirectory
        process.environment = [
            "HOME": home.path,
            "CODEX_HOME": home.path,
            "TMPDIR": temporaryDirectory.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            let nsError = error as NSError
            let allowedDomains = [NSPOSIXErrorDomain, NSCocoaErrorDomain]
            return VersionResult(
                status: nsError.code == EPERM || nsError.code == EACCES ? "launch_denied" : "spawn_error",
                exitCode: nil,
                signal: nil,
                errorDomain: allowedDomains.contains(nsError.domain) ? nsError.domain : "other",
                errorCode: nsError.code,
                timedOut: false,
                cleanup: "not_started",
                cleanupPID: nil,
                killResult: nil,
                killErrno: nil
            )
        }

        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            let cleanupDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < cleanupDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                let pid = process.processIdentifier
                let killResult = Darwin.kill(pid, SIGKILL)
                let killErrno: Int? = killResult == 0 ? nil : Int(errno)
                let reapDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < reapDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if !process.isRunning {
                    process.waitUntilExit()
                }
                return VersionResult(
                    status: "timeout",
                    exitCode: nil,
                    signal: process.isRunning
                        ? Int(SIGKILL)
                        : (process.terminationReason == .uncaughtSignal ? Int(process.terminationStatus) : nil),
                    errorDomain: nil,
                    errorCode: nil,
                    timedOut: true,
                    cleanup: process.isRunning
                        ? (killResult == 0 ? "sigkill_sent_reap_timeout" : "sigkill_failed_reap_timeout")
                        : "sigkill_attempted_reaped",
                    cleanupPID: process.isRunning ? Int(pid) : nil,
                    killResult: Int(killResult),
                    killErrno: killErrno
                )
            }
            return VersionResult(
                status: "timeout",
                exitCode: nil,
                signal: process.terminationReason == .uncaughtSignal ? Int(process.terminationStatus) : nil,
                errorDomain: nil,
                errorCode: nil,
                timedOut: true,
                cleanup: "terminated_after_timeout",
                cleanupPID: nil,
                killResult: nil,
                killErrno: nil
            )
        }

        let succeeded = process.terminationReason == .exit && process.terminationStatus == 0
        return VersionResult(
            status: succeeded ? "passed" : "nonzero_exit",
            exitCode: process.terminationReason == .exit ? Int(process.terminationStatus) : nil,
            signal: process.terminationReason == .uncaughtSignal ? Int(process.terminationStatus) : nil,
            errorDomain: nil,
            errorCode: nil,
            timedOut: false,
            cleanup: "exited",
            cleanupPID: nil,
            killResult: nil,
            killErrno: nil
        )
    }

    private func runReadOnlyRPC(
        executable: String,
        home: URL,
        workingDirectory: URL,
        temporaryDirectory: URL
    ) -> RPCSummary {
        ReadOnlyAppServerProbe(
            executable: executable,
            home: home,
            workingDirectory: workingDirectory,
            temporaryDirectory: temporaryDirectory
        ).run()
    }

    private func isDescendant(_ candidate: URL, of parent: URL) -> Bool {
        candidate.standardizedFileURL.path.hasPrefix(parent.standardizedFileURL.path + "/")
    }

    private func writeReport(_ report: [String: Any], to url: URL) {
        guard JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

private enum RPCExchange {
    case result([String: Any])
    case rpcError(code: Int?, authenticationRequired: Bool)
    case timeout
    case processExited
    case invalidResponse
    case transportError
}

private enum LineReadResult {
    case line(Data)
    case timeout
    case closed
    case tooLarge
}

private struct JSONLineBuffer {
    private(set) var data = Data()

    mutating func append(_ fragment: Data) -> Bool {
        data.append(fragment)
        return data.count <= 1_048_576
    }

    mutating func takeLine() -> Data? {
        guard let newline = data.firstIndex(of: 0x0A) else { return nil }
        let line = Data(data[..<newline])
        data.removeSubrange(data.startIndex...newline)
        return line
    }
}

private func readJSONLine(
    from descriptor: Int32,
    buffer: inout JSONLineBuffer,
    timeoutMilliseconds: Int
) -> LineReadResult {
    let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000)
    while Date() < deadline {
        if let line = buffer.takeLine() { return .line(line) }
        let remaining = max(1, Int(deadline.timeIntervalSinceNow * 1_000))
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let pollResult = Darwin.poll(&pollDescriptor, 1, Int32(remaining))
        if pollResult == 0 { return .timeout }
        if pollResult < 0 {
            if errno == EINTR { continue }
            return .closed
        }
        var bytes = [UInt8](repeating: 0, count: 8_192)
        let count = bytes.withUnsafeMutableBytes { rawBuffer in
            Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
        }
        if count == 0 { return .closed }
        if count < 0 {
            if errno == EINTR || errno == EAGAIN { continue }
            return .closed
        }
        guard buffer.append(Data(bytes.prefix(count))) else { return .tooLarge }
    }
    return .timeout
}

private func accountReadCategory(_ result: [String: Any]) -> String {
    if let account = result["account"] as? [String: Any] {
        if let type = account["type"] as? String, !type.isEmpty {
            return "account_present"
        }
        return "account_present_unclassified"
    }
    if result["requiresOpenaiAuth"] as? Bool == true {
        return "unauthenticated"
    }
    return "response_unclassified"
}

private enum SandboxProbeSelfTest {
    static func run() -> Bool {
        var pipeDescriptors: [Int32] = [0, 0]
        guard Darwin.pipe(&pipeDescriptors) == 0 else { return false }
        let writerFinished = DispatchSemaphore(value: 0)
        let firstFragment = Data("{\"jsonrpc\":\"2.0\",\"id\":".utf8)
        let secondFragment = Data("7,\"result\":{}}\n".utf8)
        let readDescriptor = pipeDescriptors[0]
        let writeDescriptor = pipeDescriptors[1]
        DispatchQueue.global(qos: .userInitiated).async {
            _ = firstFragment.withUnsafeBytes { Darwin.write(writeDescriptor, $0.baseAddress, $0.count) }
            usleep(50_000)
            _ = secondFragment.withUnsafeBytes { Darwin.write(writeDescriptor, $0.baseAddress, $0.count) }
            Darwin.close(writeDescriptor)
            writerFinished.signal()
        }
        var buffer = JSONLineBuffer()
        let readResult = readJSONLine(from: readDescriptor, buffer: &buffer, timeoutMilliseconds: 2_000)
        let writerDidFinish = writerFinished.wait(timeout: .now() + 1) == .success
        Darwin.close(readDescriptor)
        guard writerDidFinish, case .line(let line) = readResult,
              let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              message["id"] as? Int == 7,
              buffer.takeLine() == nil else {
            return false
        }

        let accountResponse: [String: Any] = [
            "account": ["type": "chatgpt"],
            "requiresOpenaiAuth": true
        ]
        let unauthenticatedResponse: [String: Any] = ["requiresOpenaiAuth": true]
        return accountReadCategory(accountResponse) == "account_present"
            && accountReadCategory(unauthenticatedResponse) == "unauthenticated"
            && !sandboxProbeLoginActionEnabled(sessionAvailable: true, loginPending: false, busy: true)
            && sandboxProbeLoginActionEnabled(sessionAvailable: true, loginPending: false, busy: false)
            && sandboxProbeLoginCancelConfirmed(.result([:]))
            && !sandboxProbeLoginCancelConfirmed(.timeout)
            && !sandboxProbeLoginCancelConfirmed(.closed)
            && sandboxProbeLoginStartFailureCode(.rpcError(authenticationRequired: false)) == .loginStartRPCError
            && sandboxProbeLoginStartFailureCode(.rpcError(authenticationRequired: true)) == .loginStartAuthenticationRequired
            && sandboxProbeLoginStartFailureCode(.timeout) == .loginStartTimeout
            && sandboxProbeLoginStartFailureCode(.closed) == .loginStartClosed
            && sandboxProbeLoginStartFailureCode(.invalid) == .loginStartInvalidRPCResponse
            && sandboxProbeLoginStartFailureCode(.result([:])) == nil
            && sandboxProbeLoginStartPayloadFailureCode(loginID: nil, authURLText: "https://example.invalid/") == .loginStartInvalidResultSchema
            && sandboxProbeLoginStartPayloadFailureCode(loginID: "id", authURLText: "http://127.0.0.1/") == .loginStartInvalidAuthURL
            && sandboxProbeLoginStartPayloadFailureCode(loginID: "id", authURLText: "https://example.invalid/") == nil
    }
}

private struct LoopbackListenerSelfTestResult {
    let code: SandboxProbeDiagnosticCode
    let systemCode: Int?
}

private func loopbackListenerSelfTest() -> LoopbackListenerSelfTestResult {
    let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        let errorCode = errno
        return LoopbackListenerSelfTestResult(
            code: errorCode == EPERM || errorCode == EACCES
                ? .loopbackSocketPermissionDenied : .loopbackSocketFailed,
            systemCode: Int(errorCode)
        )
    }
    defer { Darwin.close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0)
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        let errorCode = errno
        let code: SandboxProbeDiagnosticCode
        if errorCode == EPERM || errorCode == EACCES {
            code = .loopbackBindPermissionDenied
        } else if errorCode == EADDRINUSE {
            code = .loopbackBindAddressInUse
        } else {
            code = .loopbackBindFailed
        }
        return LoopbackListenerSelfTestResult(code: code, systemCode: Int(errorCode))
    }

    guard Darwin.listen(descriptor, 1) == 0 else {
        let errorCode = errno
        return LoopbackListenerSelfTestResult(
            code: errorCode == EPERM || errorCode == EACCES
                ? .loopbackListenPermissionDenied : .loopbackListenFailed,
            systemCode: Int(errorCode)
        )
    }
    return LoopbackListenerSelfTestResult(code: .loopbackListenPassed, systemCode: nil)
}

private struct RPCSummary {
    let initialize: String
    let initializeErrorCode: Int?
    let accountRead: String
    let accountReadErrorCode: Int?
    let rateLimitsRead: String
    let rateLimitsErrorCode: Int?
    let cleanup: String
    let processExitCode: Int?
    let cleanupPID: Int?
    let killResult: Int?
    let killErrno: Int?

    var jsonObject: [String: Any] {
        [
            "initialize": initialize,
            "initializeErrorCode": initializeErrorCode as Any? ?? NSNull(),
            "accountRead": accountRead,
            "accountReadErrorCode": accountReadErrorCode as Any? ?? NSNull(),
            "rateLimitsRead": rateLimitsRead,
            "rateLimitsErrorCode": rateLimitsErrorCode as Any? ?? NSNull(),
            "processCleanup": cleanup,
            "processExitCode": processExitCode as Any? ?? NSNull(),
            "processCleanupPID": cleanupPID as Any? ?? NSNull(),
            "processKillResult": killResult as Any? ?? NSNull(),
            "processKillErrno": killErrno as Any? ?? NSNull()
        ]
    }
}

private final class ReadOnlyAppServerProbe {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var outputBuffer = JSONLineBuffer()
    private let timeoutMilliseconds = 8_000

    init(executable: String, home: URL, workingDirectory: URL, temporaryDirectory: URL) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = workingDirectory
        process.environment = [
            "HOME": home.path,
            "CODEX_HOME": home.path,
            "TMPDIR": temporaryDirectory.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    func run() -> RPCSummary {
        do {
            try process.run()
        } catch {
            let nsError = error as NSError
            let denied = nsError.code == EPERM || nsError.code == EACCES
            let status = denied ? "launch_denied" : "spawn_error"
            return RPCSummary(
                initialize: status,
                initializeErrorCode: nsError.code,
                accountRead: "not_attempted",
                accountReadErrorCode: nil,
                rateLimitsRead: "not_attempted",
                rateLimitsErrorCode: nil,
                cleanup: "not_started",
                processExitCode: nil,
                cleanupPID: nil,
                killResult: nil,
                killErrno: nil
            )
        }

        let initialize = exchange(method: "initialize", id: 1, params: [
            "clientInfo": ["name": "AIUsageBuddy Sandbox Probe", "version": "0.1.0"]
        ])
        var accountStatus = "not_attempted"
        var accountCode: Int?
        var limitsStatus = "not_attempted"
        var limitsCode: Int?

        if case .result = initialize {
            sendNotification(method: "initialized", params: [:])
            let accountReply = exchange(method: "account/read", id: 2, params: [:])
            accountStatus = accountStatusFor(accountReply)
            accountCode = errorCode(from: accountReply)

            let limitsReply = exchange(method: "account/rateLimits/read", id: 3, params: [:])
            limitsStatus = statusForRead(limitsReply)
            limitsCode = errorCode(from: limitsReply)
        }

        let initStatus = statusForInitialize(initialize)
        let initCode = errorCode(from: initialize)
        let cleanup = stop()
        return RPCSummary(
            initialize: initStatus,
            initializeErrorCode: initCode,
            accountRead: accountStatus,
            accountReadErrorCode: accountCode,
            rateLimitsRead: limitsStatus,
            rateLimitsErrorCode: limitsCode,
            cleanup: cleanup.status,
            processExitCode: cleanup.exitCode,
            cleanupPID: cleanup.pid,
            killResult: cleanup.killResult,
            killErrno: cleanup.killErrno
        )
    }

    private func exchange(method: String, id: Int, params: [String: Any]) -> RPCExchange {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        guard let body = try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]) else {
            return .invalidResponse
        }
        do {
            try input.fileHandleForWriting.write(contentsOf: body + Data([0x0A]))
        } catch {
            return .transportError
        }

        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000)
        while Date() < deadline {
            let remaining = max(1, Int(deadline.timeIntervalSinceNow * 1_000))
            switch readLine(timeoutMilliseconds: remaining) {
            case .line(let line):
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let responseID = message["id"] as? Int,
                      responseID == id else {
                    // Notifications and non-JSON lines are discarded; never log raw RPC data.
                    continue
                }
                if let error = message["error"] as? [String: Any] {
                    let text = (error["message"] as? String ?? "").lowercased()
                    return .rpcError(
                        code: error["code"] as? Int,
                        authenticationRequired: text.contains("authentication required")
                    )
                }
                if let result = message["result"] as? [String: Any] {
                    return .result(result)
                }
                return .invalidResponse
            case .timeout:
                return .timeout
            case .closed:
                return process.isRunning ? .timeout : .processExited
            case .tooLarge:
                return .invalidResponse
            }
        }
        return .timeout
    }

    private func readLine(timeoutMilliseconds: Int) -> LineReadResult {
        let descriptor = output.fileHandleForReading.fileDescriptor
        return readJSONLine(from: descriptor, buffer: &outputBuffer, timeoutMilliseconds: timeoutMilliseconds)
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let notification: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        guard let body = try? JSONSerialization.data(withJSONObject: notification, options: [.sortedKeys]) else { return }
        try? input.fileHandleForWriting.write(contentsOf: body + Data([0x0A]))
    }

    private func statusForInitialize(_ exchange: RPCExchange) -> String {
        switch exchange {
        case .result: return "passed"
        case .rpcError(_, let auth): return auth ? "authentication_required" : "rpc_error"
        case .timeout: return "timeout"
        case .processExited: return "process_exited"
        case .invalidResponse: return "invalid_response"
        case .transportError: return "transport_error"
        }
    }

    private func accountStatusFor(_ exchange: RPCExchange) -> String {
        switch exchange {
        case .result(let result): return accountReadCategory(result)
        case .rpcError(_, let auth): return auth ? "authentication_required" : "rpc_error"
        case .timeout: return "timeout"
        case .processExited: return "process_exited"
        case .invalidResponse: return "invalid_response"
        case .transportError: return "transport_error"
        }
    }

    private func statusForRead(_ exchange: RPCExchange) -> String {
        switch exchange {
        case .result: return "read_succeeded"
        case .rpcError(_, let auth): return auth ? "authentication_required" : "rpc_error"
        case .timeout: return "timeout"
        case .processExited: return "process_exited"
        case .invalidResponse: return "invalid_response"
        case .transportError: return "transport_error"
        }
    }

    private func errorCode(from exchange: RPCExchange) -> Int? {
        guard case .rpcError(let code, _) = exchange else { return nil }
        return code
    }

    private func stop() -> (status: String, exitCode: Int?, pid: Int?, killResult: Int?, killErrno: Int?) {
        guard process.isRunning else {
            return ("already_exited", process.terminationReason == .exit ? Int(process.terminationStatus) : nil, nil, nil, nil)
        }
        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            let pid = process.processIdentifier
            let killResult = Darwin.kill(pid, SIGKILL)
            let killErrno: Int? = killResult == 0 ? nil : Int(errno)
            let reapDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < reapDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if !process.isRunning {
                process.waitUntilExit()
                return (
                    "sigkill_attempted_reaped",
                    process.terminationReason == .exit ? Int(process.terminationStatus) : nil,
                    nil,
                    Int(killResult),
                    killErrno
                )
            }
            return (
                killResult == 0 ? "sigkill_sent_reap_timeout" : "sigkill_failed_reap_timeout",
                nil,
                Int(pid),
                Int(killResult),
                killErrno
            )
        }
        return ("terminated", process.terminationReason == .exit ? Int(process.terminationStatus) : nil, nil, nil, nil)
    }
}

private struct VersionResult {
    let status: String
    let exitCode: Int?
    let signal: Int?
    let errorDomain: String?
    let errorCode: Int?
    let timedOut: Bool
    let cleanup: String
    let cleanupPID: Int?
    let killResult: Int?
    let killErrno: Int?
}

@main
private struct SandboxProbeApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = ProbeDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }
}
