#if AI_USAGE_BUDDY_APP_STORE && AI_USAGE_BUDDY_RUNTIME_VALIDATION
import AppKit
import Darwin
import Foundation

@MainActor
@main
enum StoreRuntimeValidationEntry {
    static var exitStatus: Int32 = 60

    static func main() {
        guard let runUUID = StoreRuntimeValidationRunner.runUUIDFromArguments(CommandLine.arguments) else {
            Darwin.exit(61)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = StoreRuntimeValidationDelegate(runUUID: runUUID)
        application.delegate = delegate
        application.run()
        Darwin.exit(exitStatus)
    }
}

@MainActor
private final class StoreRuntimeValidationDelegate: NSObject, NSApplicationDelegate {
    private let runUUID: UUID
    private var runTask: Task<Void, Never>?
    private var terminationRequested = false
    private var runFinished = false

    init(runUUID: UUID) {
        self.runUUID = runUUID
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        runTask = Task { [weak self] in
            guard let self else {
                NSApp.terminate(nil)
                return
            }
            let status = await StoreRuntimeValidationRunner.run(runUUID: runUUID)
            StoreRuntimeValidationEntry.exitStatus = status
            runFinished = true
            if terminationRequested {
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !runFinished else { return .terminateNow }
        terminationRequested = true
        runTask?.cancel()
        return .terminateLater
    }
}

private enum StoreRuntimeValidationRunner {
    private static let expectedBundleIdentifier = "com.aiusagebuddy.app.store.validation"

    private enum Status {
        static let passed = 0
        static let running = 1
        static let invalidBundle = 10
        static let invalidSandboxHome = 11
        static let setupFailed = 12
        static let rpcFailed = 20
        static let accountStateUnexpected = 30
        static let rateLimitsNotAuthenticationGated = 40
        static let quotaUnexpectedlyReturned = 41
        static let shutdownIncomplete = 50
        static let reportWriteFailed = 60
    }

    static func runUUIDFromArguments(_ arguments: [String]) -> UUID? {
        guard arguments.count == 3,
              arguments[1] == "--run-uuid",
              let runUUID = UUID(uuidString: arguments[2]),
              runUUID.uuidString.caseInsensitiveCompare(arguments[2]) == .orderedSame
        else {
            return nil
        }
        return runUUID
    }

    private struct Report: Encodable {
        let schemaVersion: Int
        let runUUID: UUID
        let bundleIdentifier: String
        var statusCode: Int
        var sandboxContainerValidated = false
        var initializeSucceeded = false
        var accountReadSucceeded = false
        var accountIsNil: Bool?
        var requiresOpenAIAuth: Bool?
        var rateLimitsRequiresAuthentication: Bool?
        var rateLimitRPCErrorCode: Int?
        var unexpectedQuotaResponse = false
        var shutdownCompleted = false
        var ownedProcessIDs: [Int32] = []
    }

    private enum ValidationError: Error {
        case invalidBundle
        case invalidSandboxHome
        case setupFailed
    }

    static func run(runUUID: UUID) async -> Int32 {
        var report = Report(
            schemaVersion: 1,
            runUUID: runUUID,
            bundleIdentifier: expectedBundleIdentifier,
            statusCode: Status.running
        )
        var reportURL: URL?
        var client: CodexAppServerClient?

        do {
            guard Bundle.main.bundleIdentifier == expectedBundleIdentifier else {
                throw ValidationError.invalidBundle
            }
            let sandboxHome = try validatedSandboxHome()
            report.sandboxContainerValidated = true

            let runRoot = sandboxHome
                .appendingPathComponent("Library/Application Support/AI Usage Buddy/StoreRuntimeValidation", isDirectory: true)
                .appendingPathComponent(runUUID.uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
            let canonicalHome = sandboxHome.resolvingSymlinksInPath().standardizedFileURL
            let canonicalRunRoot = runRoot.resolvingSymlinksInPath().standardizedFileURL
            let homePrefix = canonicalHome.path.hasSuffix("/") ? canonicalHome.path : canonicalHome.path + "/"
            guard canonicalRunRoot.path.hasPrefix(homePrefix) else {
                throw ValidationError.invalidSandboxHome
            }
            reportURL = canonicalRunRoot.appendingPathComponent("Report.json")

            let managedAccountID = UUID()
            let codexHome = canonicalRunRoot
                .appendingPathComponent("Homes", isDirectory: true)
                .appendingPathComponent(managedAccountID.uuidString, isDirectory: true)
            let runtimeClient = CodexAppServerClient(
                codexHome: codexHome,
                clientName: "AI Usage Buddy Store Runtime Validation",
                clientVersion: "1.0.1",
                distributionChannel: .appStore,
                bundleURL: Bundle.main.bundleURL,
                accountID: managedAccountID,
                containerDirectory: canonicalRunRoot
            )
            client = runtimeClient

            do {
                try Task.checkCancellation()
                try await runtimeClient.start()
                report.initializeSucceeded = true

                try Task.checkCancellation()
                let accountResponse = try await runtimeClient.readAccount()
                report.accountReadSucceeded = true
                report.accountIsNil = accountResponse.account == nil
                report.requiresOpenAIAuth = accountResponse.requiresOpenaiAuth
                guard accountResponse.account == nil, accountResponse.requiresOpenaiAuth else {
                    report.statusCode = Status.accountStateUnexpected
                    throw ValidationError.setupFailed
                }

                try Task.checkCancellation()
                do {
                    _ = try await runtimeClient.readRateLimits()
                    report.unexpectedQuotaResponse = true
                    report.statusCode = Status.quotaUnexpectedlyReturned
                } catch {
                    let result = authenticationRequired(from: error)
                    report.rateLimitsRequiresAuthentication = result.required
                    report.rateLimitRPCErrorCode = result.rpcCode
                    report.statusCode = result.required
                        ? Status.passed
                        : Status.rateLimitsNotAuthenticationGated
                }
            } catch {
                if report.statusCode == Status.running {
                    report.statusCode = Status.rpcFailed
                }
            }
        } catch ValidationError.invalidBundle {
            report.statusCode = Status.invalidBundle
        } catch ValidationError.invalidSandboxHome {
            report.statusCode = Status.invalidSandboxHome
        } catch {
            if report.statusCode == Status.running {
                report.statusCode = Status.setupFailed
            }
        }

        if let client {
            await client.stop()
            report.ownedProcessIDs = await client.ownedProcessIDsForRuntimeValidation
            report.shutdownCompleted = report.ownedProcessIDs.isEmpty
            if !report.shutdownCompleted {
                report.statusCode = Status.shutdownIncomplete
            }
        } else {
            report.shutdownCompleted = true
        }

        guard let reportURL else { return Int32(report.statusCode) }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: reportURL, options: .atomic)
        } catch {
            return Int32(Status.reportWriteFailed)
        }
        return Int32(report.statusCode)
    }

    private static func validatedSandboxHome() throws -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let expectedSuffix = ["Library", "Containers", expectedBundleIdentifier, "Data"]
        guard Array(home.pathComponents.suffix(expectedSuffix.count)) == expectedSuffix else {
            throw ValidationError.invalidSandboxHome
        }
        return home
    }

    private static func authenticationRequired(from error: Error) -> (required: Bool, rpcCode: Int?) {
        guard let clientError = error as? CodexClientError else { return (false, nil) }
        switch clientError {
        case .authenticationRequired:
            return (true, nil)
        case .serverError(let code, let message):
            return (message.localizedCaseInsensitiveContains("authentication required"), code)
        default:
            return (false, nil)
        }
    }
}
#endif
