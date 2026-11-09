import Foundation
import Testing
@testable import AIUsageBuddy

@Suite
@MainActor
struct StoreIsolationTests {

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUsageBuddy-StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test-helper".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeMockStoreBundle(
        at bundle: URL,
        replyDelay: String = "0.15",
        startupMarker: URL? = nil,
        stopMarker: URL? = nil,
        holdInitialize: Bool = false,
        failLoginStart: Bool = false,
        failLogout: Bool = false,
        logoutMarker: URL? = nil,
        logoutDelay: String = "0",
        floodStderr: Bool = false,
        rateLimitsCapture: URL? = nil
    ) throws {
        let helper = bundle.appendingPathComponent("Contents/Helpers/codex-app-server")
        let stopTrap = stopMarker.map {
            "trap 'printf stopped > \(shellQuote($0.path))' TERM\n"
        } ?? ""
        let initializeResponse: String
        if holdInitialize, let startupMarker {
            let marker = shellQuote(startupMarker.path)
            initializeResponse = """
            if [ ! -e \(marker) ]; then
              printf ready > \(marker)
              while IFS= read -r ignored; do :; done
            else
              printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
            fi
            """
        } else {
            let startupMarkerWrite = startupMarker.map {
                "printf ready > \(shellQuote($0.path))\n"
            } ?? ""
            initializeResponse = startupMarkerWrite
                + (floodStderr ? "/usr/bin/head -c 2097152 /dev/zero >&2\n" : "")
                + "/bin/sleep \(replyDelay)\n"
                + "request_id=$(printf '%s\\n' \"$line\" | /usr/bin/sed -E 's/.*\"id\":([0-9]+).*/\\1/')\n"
                + "printf '%s\\n' \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":$request_id,\\\"result\\\":{}}\""
        }
        let loginStartCase = failLoginStart ? """
          *account*)
            request_id=$(printf '%s\\n' "$line" | /usr/bin/sed -E 's/.*"id":([0-9]+).*/\\1/')
            printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32000,"message":"fixture failure"}}\\n' "$request_id"
            ;;
        """ : ""
        let logoutMarkerWrite = logoutMarker.map { "printf logout > \(shellQuote($0.path))\n" } ?? ""
        let rateLimitsCaptureWrite = rateLimitsCapture.map {
            "printf '%s\\n' \"$line\" > \(shellQuote($0.path))\n"
        } ?? ""
        let logoutReply = failLogout
            ? "\"error\":{\"code\":-32000,\"message\":\"fixture logout failure\"}"
            : "\"result\":{}"
        let script = """
        #!/bin/sh
        \(stopTrap)while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*)
              \(initializeResponse)
              ;;
            *account*rateLimits*read*)
              \(rateLimitsCaptureWrite)request_id=$(printf '%s\\n' "$line" | /usr/bin/sed -E 's/.*"id":([0-9]+).*/\\1/')
              printf '{"jsonrpc":"2.0","id":%s,"result":{"rateLimits":{"primary":{"usedPercent":25,"resetsAt":1800000000,"windowDurationMins":300},"secondary":{"usedPercent":40,"resetsAt":1800500000,"windowDurationMins":10080}}}}\\n' "$request_id"
              ;;
            *account*logout*)
              \(logoutMarkerWrite)/bin/sleep \(logoutDelay)
              request_id=$(printf '%s\\n' "$line" | /usr/bin/sed -E 's/.*"id":([0-9]+).*/\\1/')
              printf '{"jsonrpc":"2.0","id":%s,\(logoutReply)}\\n' "$request_id"
              ;;
        \(loginStartCase)  esac
        done
        """
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    }

    @Test("Quota poll captures Store camelCase exclusion and unchanged Direct params",
          arguments: [DistributionChannel.direct, .appStore])
    func rateLimitsRequestPrivacyParams(_ channel: DistributionChannel) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("QuotaFixture.app")
        let capture = root.appendingPathComponent("request.json")
        try makeMockStoreBundle(at: bundle, replyDelay: "0", rateLimitsCapture: capture)
        let id = UUID()
        let home = try AccountStore(containerDirectory: root).prepareManagedHome(for: id)
        let client = CodexAppServerClient(
            executableURL: bundle.appendingPathComponent("Contents/Helpers/codex-app-server"),
            codexHome: home, distributionChannel: channel, bundleURL: bundle,
            accountID: id, containerDirectory: root
        )
        do {
            try await client.start()
            let response = try await client.readRateLimits()
            await client.stop()
            let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: capture)) as? [String: Any])
            #expect(json["method"] as? String == "account/rateLimits/read")
            let params = try #require(json["params"] as? [String: Any])
            if channel.isAppStore {
                #expect(Set(params.keys) == Set(["excludeResetCreditDetails"]))
                #expect(params["excludeResetCreditDetails"] as? Bool == true)
            } else {
                #expect(params.isEmpty)
            }
            #expect(response.rateLimits.primary?.usedPercent == 25)
            #expect(response.rateLimits.primary?.resetsAt == 1800000000)
            #expect(response.rateLimits.primary?.windowDurationMins == 300)
            #expect(response.rateLimits.secondary?.usedPercent == 40)
            #expect(response.rateLimits.secondary?.resetsAt == 1800500000)
            #expect(response.rateLimits.secondary?.windowDurationMins == 10080)
        } catch {
            await client.stop()
            throw error
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func makeTermIgnoringStoreBundle(at bundle: URL) throws {
        let helper = bundle.appendingPathComponent("Contents/Helpers/codex-app-server")
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let source = helper.appendingPathExtension("c")
        let program = #"""
        #include <signal.h>
        #include <stdio.h>
        #include <string.h>
        #include <unistd.h>

        int main(void) {
            signal(SIGTERM, SIG_IGN);
            char line[4096];
            while (fgets(line, sizeof(line), stdin) != NULL) {
                if (strstr(line, "\"method\":\"initialize\"") != NULL) {
                    fputs("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n", stdout);
                    fflush(stdout);
                }
            }
            for (;;) pause();
        }
        """#
        try Data(program.utf8).write(to: source)

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-std=c11", "-O0", source.path, "-o", helper.path]
        compiler.standardOutput = Pipe()
        compiler.standardError = Pipe()
        try compiler.run()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else {
            throw NSError(domain: "StoreIsolationTests", code: Int(compiler.terminationStatus))
        }
    }

    @Test("compile flag selects the distribution channel while default builds remain direct")
    func compileFlagSelectsChannel() {
        #if AI_USAGE_BUDDY_APP_STORE
        #expect(DistributionChannel.current == .appStore)
        #else
        #expect(DistributionChannel.current == .direct)
        #endif
    }

    @Test("Store resolver accepts only the executable inside the app helper directory")
    func storeResolverUsesBundledHelper() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("AIUsageBuddy.app", isDirectory: true)
        let helper = bundle.appendingPathComponent("Contents/Helpers/codex-app-server")
        let external = root.appendingPathComponent("external-codex")
        try makeExecutable(at: helper)
        try makeExecutable(at: external)

        let resolved = try CodexExecutableResolver.resolve(
            channel: .appStore,
            bundleURL: bundle,
            explicitURL: external
        )
        #expect(resolved.url == helper.resolvingSymlinksInPath().standardizedFileURL)
        #expect(resolved.kind == .standaloneAppServer)
    }

    @Test("Store runtime policy uses the exact audited public override values")
    func storeRuntimePolicyUsesAuditedValues() {
        #expect(AppServerRuntimePolicy.storeConfigOverrides == [
            "cli_auth_credentials_store=\"keyring\"",
            "features.secret_auth_storage=false",
            "features.plugins=false",
            "analytics.enabled=false",
            "otel.exporter=\"none\"",
            "otel.trace_exporter=\"none\"",
            "otel.metrics_exporter=\"none\"",
        ])
    }

    @Test("Store launches the standalone app-server over stdio, while direct CLI keeps its subcommand")
    func executableKindsSelectTheirLaunchArguments() async throws {
        #expect(CodexExecutableKind.cli.arguments == ["app-server"])
        let expectedStoreArguments = [
            "--config", "cli_auth_credentials_store=\"keyring\"",
            "--config", "features.secret_auth_storage=false",
            "--config", "features.plugins=false",
            "--config", "analytics.enabled=false",
            "--config", "otel.exporter=\"none\"",
            "--config", "otel.trace_exporter=\"none\"",
            "--config", "otel.metrics_exporter=\"none\"",
            "--listen", "stdio://",
        ]
        #expect(CodexExecutableKind.standaloneAppServer.arguments == expectedStoreArguments)

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("MockAIUsageBuddy.app", isDirectory: true)
        try makeMockStoreBundle(at: bundle)
        let accountID = UUID()
        let accountStore = AccountStore(containerDirectory: root)
        let home = try accountStore.prepareManagedHome(for: accountID)
        let client = CodexAppServerClient(
            codexHome: home,
            distributionChannel: .appStore,
            bundleURL: bundle,
            accountID: accountID,
            containerDirectory: root
        )

        try await client.start()
        let process = await client.processForTesting()
        #expect(process?.executableURL?.lastPathComponent == "codex-app-server")
        #expect(process?.arguments == expectedStoreArguments)
        await client.stop()
    }

    @Test("Owned logout stops its fixture helper on success and failure, and stale retries cannot stop a replacement", arguments: [false, true])
    func logoutCleanupAndStaleRetry(fails: Bool) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("LogoutFixture.app", isDirectory: true)
        let marker = root.appendingPathComponent("logout.fixture")
        try makeMockStoreBundle(at: bundle, failLogout: fails, logoutMarker: marker)
        let id = UUID()
        let home = try AccountStore(containerDirectory: root).prepareManagedHome(for: id)
        let cache = ClientCache()
        let client = try await cache.runningClient(
            for: id, codexHome: home, distributionChannel: .appStore, containerDirectory: root, bundleURL: bundle
        )
        let process = await client.processForTesting()
        var failed = false
        do {
            try await cache.logoutAndStop(for: id, codexHome: home, containerDirectory: root, bundleURL: bundle)
        } catch { failed = true }
        #expect(failed == fails)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(!(await client.isAlive()))
        #expect(process?.isRunning == false)
        if fails {
            let replacement = try await cache.runningClient(
                for: id, codexHome: home, distributionChannel: .appStore, containerDirectory: root, bundleURL: bundle
            )
            var retryRejected = false
            do {
                try await cache.restartClient(
                    for: id, codexHome: home, distributionChannel: .appStore,
                    containerDirectory: root, bundleURL: bundle, expectedClient: client
                )
            } catch { retryRejected = true }
            #expect(retryRejected)
            #expect(await replacement.isAlive())
            await cache.discardClient(for: id)
            #expect(!(await replacement.isAlive()))
        } else {
            var restartRejected = false
            do {
                _ = try await cache.runningClient(
                    for: id, codexHome: home, distributionChannel: .appStore, containerDirectory: root, bundleURL: bundle
                )
            } catch { restartRejected = true }
            #expect(restartRejected)
        }
        await cache.stopAll()
    }

    @Test("Cancellation during logout cleans the owned helper; duplicate and fetch acquisitions stay blocked")
    func cancelledLogoutStopsOwnedHelper() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("CancelledLogoutFixture.app", isDirectory: true)
        let marker = root.appendingPathComponent("logout.fixture")
        try makeMockStoreBundle(at: bundle, logoutMarker: marker, logoutDelay: "0.3")
        let id = UUID()
        let home = try AccountStore(containerDirectory: root).prepareManagedHome(for: id)
        let cache = ClientCache()
        let client = try await cache.runningClient(
            for: id, codexHome: home, distributionChannel: .appStore, containerDirectory: root, bundleURL: bundle
        )
        let process = await client.processForTesting()
        let deletion = Task { () -> Bool in
            do {
                try await cache.logoutAndStop(for: id, codexHome: home, containerDirectory: root, bundleURL: bundle)
                return true
            } catch { return false }
        }
        #expect(await waitForFile(marker))
        var duplicateRejected = false
        do {
            try await cache.logoutAndStop(for: id, codexHome: home, containerDirectory: root, bundleURL: bundle)
        } catch { duplicateRejected = true }
        #expect(duplicateRejected)
        var fetchRejected = false
        do {
            _ = try await cache.runningClient(
                for: id, codexHome: home, distributionChannel: .appStore, containerDirectory: root, bundleURL: bundle
            )
        } catch { fetchRejected = true }
        #expect(fetchRejected)
        deletion.cancel()
        #expect(!(await deletion.value))
        #expect(!(await client.isAlive()))
        #expect(process?.isRunning == false)
        await cache.stopAll()
    }

    @Test("Two MiB of helper stderr cannot block initialize and are discarded")
    func stderrFloodDoesNotBlockInitialize() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("StderrFixture.app", isDirectory: true)
        try makeMockStoreBundle(at: bundle, replyDelay: "0", floodStderr: true)
        let id = UUID()
        let home = try AccountStore(containerDirectory: root).prepareManagedHome(for: id)
        let client = CodexAppServerClient(
            codexHome: home, distributionChannel: .appStore, bundleURL: bundle,
            accountID: id, containerDirectory: root
        )
        do {
            try await client.start()
            #expect(await client.isAlive())
        } catch {
            await client.stop()
            throw error
        }
        await client.stop()
        #expect(!(await client.isAlive()))
    }

    @Test("Store resolver rejects a helper symlink escaping Contents/Helpers")
    func storeResolverRejectsHelperSymlinkEscape() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("AIUsageBuddy.app", isDirectory: true)
        let helper = bundle.appendingPathComponent("Contents/Helpers/codex-app-server")
        let external = root.appendingPathComponent("external-codex")
        try makeExecutable(at: external)
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: helper, withDestinationURL: external)

        do {
            _ = try CodexExecutableResolver.resolve(channel: .appStore, bundleURL: bundle)
            Issue.record("helper symlink outside Contents/Helpers must be rejected")
        } catch CodexClientError.storeHelperMissing {
            // Expected fail-closed result.
        }
    }

    @Test("Store resolver rejects Contents and Helpers directory symlink escapes")
    func storeResolverRejectsDirectorySymlinkEscapes() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default

        let contentsBundle = root.appendingPathComponent("ContentsLink.app", isDirectory: true)
        let externalContents = root.appendingPathComponent("external-contents", isDirectory: true)
        let externalContentsHelper = externalContents.appendingPathComponent("Helpers/codex")
        try makeExecutable(at: externalContentsHelper)
        try fileManager.createDirectory(at: contentsBundle, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: contentsBundle.appendingPathComponent("Contents", isDirectory: true),
            withDestinationURL: externalContents
        )

        let helpersBundle = root.appendingPathComponent("HelpersLink.app", isDirectory: true)
        let externalHelpers = root.appendingPathComponent("external-helpers", isDirectory: true)
        try makeExecutable(at: externalHelpers.appendingPathComponent("codex"))
        try fileManager.createDirectory(
            at: helpersBundle.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(
            at: helpersBundle.appendingPathComponent("Contents/Helpers", isDirectory: true),
            withDestinationURL: externalHelpers
        )

        for bundle in [contentsBundle, helpersBundle] {
            do {
                _ = try CodexExecutableResolver.resolve(channel: .appStore, bundleURL: bundle)
                Issue.record("Contents/Helpers directory symlink escape must be rejected")
            } catch CodexClientError.storeHelperMissing {
                // Expected fail-closed result.
            }
        }
    }

    @Test("Store resolver rejects a missing bundled helper")
    func storeResolverFailsClosedWhenHelperIsMissing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try CodexExecutableResolver.resolve(
                channel: .appStore,
                bundleURL: root.appendingPathComponent("Missing.app", isDirectory: true)
            )
            Issue.record("Store resolver must not fall back when its helper is absent")
        } catch CodexClientError.storeHelperMissing {
            // Expected fail-closed result.
        }
    }

    @Test("Store process gets only allowlisted environment and per-account container paths")
    func storeProcessEnvironmentIsAllowlistedAndScoped() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let accountID = UUID()
        let accountStore = AccountStore(containerDirectory: root)
        let home = try accountStore.prepareManagedHome(for: accountID)
        let configuration = try CodexProcessConfigurationBuilder.make(
            channel: .appStore,
            inheritedEnvironment: ["SECRET_SENTINEL": "must-not-pass", "PATH": "/untrusted"],
            codexHome: home,
            accountID: accountID,
            containerDirectory: accountStore.containerDirectory
        )

        #expect(Set(configuration.environment.keys) == Set(["HOME", "CODEX_HOME", "TMPDIR", "PATH"]))
        #expect(configuration.environment["SECRET_SENTINEL"] == nil)
        #expect(configuration.environment["HOME"] == home.resolvingSymlinksInPath().path)
        #expect(configuration.environment["CODEX_HOME"] == home.resolvingSymlinksInPath().path)
        #expect(configuration.environment["TMPDIR"]?.contains(accountID.uuidString) == true)
        #expect(configuration.environment["TMPDIR"]?.hasPrefix(root.resolvingSymlinksInPath().path) == true)
        #expect(configuration.workingDirectoryURL?.path.contains(accountID.uuidString) == true)
        #expect(configuration.workingDirectoryURL?.path.hasPrefix(root.resolvingSymlinksInPath().path) == true)
    }

    @Test("Store process rejects CODEX_HOME symlink escapes")
    func storeProcessRejectsHomeSymlinkEscape() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let accountID = UUID()
        let accountStore = AccountStore(containerDirectory: root)
        let home = accountStore.managedHomeURL(for: accountID)
        try FileManager.default.createDirectory(at: home.deletingLastPathComponent(), withIntermediateDirectories: true)
        let external = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createSymbolicLink(at: home, withDestinationURL: external)

        do {
            _ = try CodexProcessConfigurationBuilder.make(
                channel: .appStore,
                inheritedEnvironment: [:],
                codexHome: home,
                accountID: accountID,
                containerDirectory: accountStore.containerDirectory
            )
            Issue.record("CODEX_HOME symlink outside the container must be rejected")
        } catch CodexClientError.storeHomeInvalid {
            // Expected fail-closed result.
        }
    }

    @Test("ClientCache shares one in-flight startup and waits for process shutdown")
    func concurrentClientRequestsShareStartup() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("MockAIUsageBuddy.app", isDirectory: true)
        try makeMockStoreBundle(at: bundle)
        let accountID = UUID()
        let accountStore = AccountStore(containerDirectory: root)
        let home = try accountStore.prepareManagedHome(for: accountID)
        let cache = ClientCache()

        async let first = cache.runningClient(
            for: accountID,
            codexHome: home,
            distributionChannel: .appStore,
            containerDirectory: root,
            bundleURL: bundle
        )
        async let second = cache.runningClient(
            for: accountID,
            codexHome: home,
            distributionChannel: .appStore,
            containerDirectory: root,
            bundleURL: bundle
        )
        let (firstClient, secondClient) = try await (first, second)
        #expect(firstClient === secondClient)
        #expect(await firstClient.isAlive())

        await cache.discardClient(for: accountID)
        #expect(!(await firstClient.isAlive()))
    }

    @Test("Discard during startup invalidates the old generation before a replacement starts")
    func discardDuringStartupDoesNotReregisterClient() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("MockAIUsageBuddy.app", isDirectory: true)
        let startupMarker = root.appendingPathComponent("initialize-received")
        try makeMockStoreBundle(at: bundle, startupMarker: startupMarker, holdInitialize: true)
        let accountID = UUID()
        let accountStore = AccountStore(containerDirectory: root)
        let home = try accountStore.prepareManagedHome(for: accountID)
        let cache = ClientCache()
        let startup = Task {
            try await cache.runningClient(
                for: accountID,
                codexHome: home,
                distributionChannel: .appStore,
                containerDirectory: root,
                bundleURL: bundle
            )
        }

        #expect(await waitForFile(startupMarker), "discard must wait until initialize is in flight")
        await cache.discardClient(for: accountID)
        do {
            _ = try await startup.value
            Issue.record("discarded startup must not return or install its stale client")
        } catch {
            // A concurrent discard cancels startup and tears down its child.
        }

        let replacement = try await cache.runningClient(
            for: accountID,
            codexHome: home,
            distributionChannel: .appStore,
            containerDirectory: root,
            bundleURL: bundle
        )
        #expect(await replacement.isAlive())
        await cache.discardClient(for: accountID)
        #expect(!(await replacement.isAlive()))
    }

    @Test("A stale process termination callback cannot clear the current process")
    func staleTerminationDoesNotClearCurrentProcess() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("MockAIUsageBuddy.app", isDirectory: true)
        try makeMockStoreBundle(at: bundle)
        let accountID = UUID()
        let accountStore = AccountStore(containerDirectory: root)
        let home = try accountStore.prepareManagedHome(for: accountID)
        let client = CodexAppServerClient(
            codexHome: home,
            distributionChannel: .appStore,
            bundleURL: bundle,
            accountID: accountID,
            containerDirectory: root
        )
        try await client.start()
        let oldProcess = await client.processForTesting()
        #expect(oldProcess != nil)

        await client.stop()
        try await client.start()
        #expect(await client.isAlive())
        if let oldProcess {
            await client.handleTermination(for: oldProcess, status: oldProcess.terminationStatus)
        }
        #expect(await client.isAlive(), "a late callback from the stopped process must not clear its replacement")

        await client.stop()
        #expect(!(await client.isAlive()))
    }

    @Test("AppModel owns a login helper before startup and stops it when the app quits")
    func appModelStopCleansUpLoginStartup() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("MockAIUsageBuddy.app", isDirectory: true)
        let startupMarker = root.appendingPathComponent("initialize-received")
        let stopMarker = root.appendingPathComponent("terminated")
        try makeMockStoreBundle(
            at: bundle,
            replyDelay: "0.5",
            startupMarker: startupMarker,
            stopMarker: stopMarker,
            failLoginStart: true
        )
        let environment = TestEnvironment.make(
            distributionChannel: .appStore,
            codexBundleURL: bundle
        )
        defer { try? FileManager.default.removeItem(at: environment.container) }

        let beginLogin = Task { await environment.model.beginAddAccount() }
        #expect(await waitForFile(startupMarker), "the helper must reach startup before quit")
        await environment.model.stop()
        let wasStoppedByQuit = FileManager.default.fileExists(atPath: stopMarker.path)
        await beginLogin.value

        #expect(wasStoppedByQuit, "AppModel.stop must own and terminate the in-flight login helper")
        #expect(environment.model.loginFlow == .idle, "a cancelled startup must not restore a failed login UI")
    }

    @Test("A login-start error stops the unregistered helper")
    func loginStartFailureStopsHelper() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("MockAIUsageBuddy.app", isDirectory: true)
        let stopMarker = root.appendingPathComponent("terminated")
        try makeMockStoreBundle(
            at: bundle,
            stopMarker: stopMarker,
            failLoginStart: true
        )
        let environment = TestEnvironment.make(
            distributionChannel: .appStore,
            codexBundleURL: bundle
        )
        defer { try? FileManager.default.removeItem(at: environment.container) }

        await environment.model.beginAddAccount()

        guard case .failed(let errorMessage) = environment.model.loginFlow else {
            Issue.record("a login-start failure should be shown after cleanup")
            return
        }
        #expect(errorMessage.contains("fixture failure"), "the fixture must return an explicit login-start error")
        #expect(FileManager.default.fileExists(atPath: stopMarker.path))
    }

    @Test("Stop escalates to SIGKILL for a helper that ignores SIGTERM")
    func stopKillsTermIgnoringHelperWithinBound() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = root.appendingPathComponent("MockAIUsageBuddy.app", isDirectory: true)
        try makeTermIgnoringStoreBundle(at: bundle)
        let accountID = UUID()
        let accountStore = AccountStore(containerDirectory: root)
        let home = try accountStore.prepareManagedHome(for: accountID)
        let client = CodexAppServerClient(
            codexHome: home,
            distributionChannel: .appStore,
            bundleURL: bundle,
            accountID: accountID,
            containerDirectory: root
        )
        try await client.start()

        let start = Date()
        await client.stop()
        let elapsed = Date().timeIntervalSince(start)

        #expect(!(await client.isAlive()))
        #expect(elapsed < 2.5, "SIGTERM-ignore cleanup should reach SIGKILL within its bound")
    }

    @Test("Direct process retains inherited environment behavior")
    func directEnvironmentRemainsInherited() throws {
        let inherited = ["PATH": "/example/bin", "LANG": "en_US.UTF-8", "CUSTOM": "preserved"]
        let configuration = try CodexProcessConfigurationBuilder.make(
            channel: .direct,
            inheritedEnvironment: inherited,
            codexHome: nil,
            accountID: nil,
            containerDirectory: nil
        )
        #expect(configuration.environment == inherited)
        #expect(configuration.workingDirectoryURL == nil)
    }

    @Test("Direct resolver preserves explicit executable selection")
    func directResolverPreservesExplicitExecutable() throws {
        let explicit = URL(fileURLWithPath: "/custom/codex")
        let resolved = try CodexExecutableResolver.resolve(
            channel: .direct,
            bundleURL: URL(fileURLWithPath: "/unused/Test.app"),
            explicitURL: explicit
        )
        #expect(resolved.url == explicit)
        #expect(resolved.kind == .cli)
    }

    @Test("Store first account uses an isolated managed home")
    func freshStoreAccountUsesManagedHome() throws {
        let environment = TestEnvironment.makeFreshInstall(distributionChannel: .appStore)
        defer { try? FileManager.default.removeItem(at: environment.container) }

        #expect(environment.model.accounts.count == 1)
        guard let account = environment.model.accounts.first else { return }
        #expect(account.homeKind == .managed)
        let home = AccountStore(containerDirectory: environment.container).managedHomeURL(for: account.id)
        #expect(FileManager.default.fileExists(atPath: home.path))
        #expect(home.path.hasPrefix(environment.container.resolvingSymlinksInPath().path + "/Homes/"))
    }

    @Test("Store migration detaches a default-home account from its prior identity")
    func defaultHomeAccountMigratesToIsolatedHome() throws {
        let account = Account(
            displayName: "Existing",
            homeKind: .defaultHome,
            officialEmail: "old@example.invalid",
            officialPlanType: "old-plan"
        )
        let environment = TestEnvironment.make(accounts: [account], distributionChannel: .appStore)
        defer { try? FileManager.default.removeItem(at: environment.container) }

        #expect(environment.model.accounts.first?.homeKind == .managed)
        #expect(environment.model.accounts.first?.officialEmail == nil)
        #expect(environment.model.accounts.first?.officialPlanType == nil)
        #expect((try AccountStore(containerDirectory: environment.container).loadAccounts()).first?.homeKind == .managed)
    }

    @Test("Store build disables updater checks and release-page actions")
    func storeUpdaterIsDisabled() async {
        let provider = SpyUpdateProvider()
        provider.setRelease(UpdateRelease(version: "99.0.0", pageURL: URL(string: "https://example.invalid/release")))
        let defaults = UserDefaults(suiteName: "test-store-update-\(UUID().uuidString)")!
        let priorCheck = Date(timeIntervalSince1970: 1234)
        defaults.set(priorCheck, forKey: UpdateService.lastCheckKey)
        let service = UpdateService(
            provider: provider,
            defaults: defaults,
            currentVersion: "1.0.0",
            distributionChannel: .appStore
        )

        await service.automaticCheckIfNeeded(enabled: true)
        await service.checkNow()
        #expect(provider.fetchCount == 0)
        #expect(service.outcome == .idle)
        #expect(defaults.object(forKey: UpdateService.lastCheckKey) as? Date == priorCheck)
        #expect(service.requestInstall(userConfirmed: true) == .managedByAppStore)
        #expect(!service.openReleasePage())
    }

    @Test("Store context menu omits update checking while direct default keeps it")
    func storeMenuOmitsUpdateCheck() {
        let direct = MenuBarContextMenuBuilder.descriptor(
            accounts: [], selectedAccountID: nil, isRefreshing: false
        )
        let store = MenuBarContextMenuBuilder.descriptor(
            accounts: [], selectedAccountID: nil, isRefreshing: false, includeUpdateCheck: false
        )
        #expect(direct.contains { $0.kind == .action(.checkForUpdates) })
        #expect(!store.contains { $0.kind == .action(.checkForUpdates) })
    }
}
