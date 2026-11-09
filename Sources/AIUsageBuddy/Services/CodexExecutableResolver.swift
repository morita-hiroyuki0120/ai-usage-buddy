import Foundation

enum CodexExecutableKind: Equatable, Sendable {
    case cli
    case standaloneAppServer

    var arguments: [String] {
        switch self {
        case .cli:
            ["app-server"]
        case .standaloneAppServer:
            AppServerRuntimePolicy.storeArguments
        }
    }
}

struct CodexExecutable {
    let url: URL
    let kind: CodexExecutableKind
}

/// Selects the Codex executable permitted by the app's distribution channel.
enum CodexExecutableResolver {
    static func resolve(
        channel: DistributionChannel,
        bundleURL: URL,
        explicitURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> CodexExecutable {
        if channel.isAppStore {
            let bundleRoot = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
            let contentsDirectory = bundleRoot.appendingPathComponent("Contents", isDirectory: true)
            let helpersDirectory = contentsDirectory.appendingPathComponent("Helpers", isDirectory: true)
            let helperURL = helpersDirectory.appendingPathComponent("codex-app-server")
            guard fileManager.fileExists(atPath: helperURL.path),
                  fileManager.isExecutableFile(atPath: helperURL.path) else {
                throw CodexClientError.storeHelperMissing
            }

            let canonicalContentsDirectory = contentsDirectory.resolvingSymlinksInPath().standardizedFileURL
            let canonicalHelpersDirectory = helpersDirectory.resolvingSymlinksInPath().standardizedFileURL
            let canonicalHelperURL = helperURL.resolvingSymlinksInPath().standardizedFileURL
            guard canonicalContentsDirectory.path == contentsDirectory.standardizedFileURL.path,
                  canonicalHelpersDirectory.path == helpersDirectory.standardizedFileURL.path else {
                throw CodexClientError.storeHelperMissing
            }
            let allowedPrefix = canonicalHelpersDirectory.path.hasSuffix("/")
                ? canonicalHelpersDirectory.path
                : canonicalHelpersDirectory.path + "/"
            guard canonicalHelperURL.path.hasPrefix(allowedPrefix) else {
                throw CodexClientError.storeHelperMissing
            }
            return CodexExecutable(url: canonicalHelperURL, kind: .standaloneAppServer)
        }

        if let explicitURL {
            return CodexExecutable(url: explicitURL, kind: .cli)
        }
        if fileManager.fileExists(atPath: CodexAppServerClient.bundledBinaryPath) {
            return CodexExecutable(
                url: URL(fileURLWithPath: CodexAppServerClient.bundledBinaryPath),
                kind: .cli
            )
        }
        return CodexExecutable(url: URL(fileURLWithPath: "codex"), kind: .cli)
    }
}
