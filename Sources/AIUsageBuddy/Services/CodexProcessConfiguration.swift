import Foundation

struct CodexProcessConfiguration {
    let environment: [String: String]
    let workingDirectoryURL: URL?
}

enum CodexProcessConfigurationBuilder {
    static func make(
        channel: DistributionChannel,
        inheritedEnvironment: [String: String],
        codexHome: URL?,
        accountID: UUID?,
        containerDirectory: URL?,
        fileManager: FileManager = .default
    ) throws -> CodexProcessConfiguration {
        guard channel.isAppStore else {
            var environment = inheritedEnvironment
            if let codexHome {
                environment["CODEX_HOME"] = codexHome.path
            }
            return CodexProcessConfiguration(environment: environment, workingDirectoryURL: nil)
        }

        guard let accountID, let codexHome, let containerDirectory else {
            throw CodexClientError.storeHomeInvalid
        }

        do {
            try fileManager.createDirectory(at: containerDirectory, withIntermediateDirectories: true)
            let containerRoot = containerDirectory.standardizedFileURL.resolvingSymlinksInPath()
            let expectedHome = containerRoot
                .appendingPathComponent("Homes", isDirectory: true)
                .appendingPathComponent(accountID.uuidString, isDirectory: true)
                .standardizedFileURL

            guard codexHome.standardizedFileURL.resolvingSymlinksInPath().path == expectedHome.path else {
                throw CodexClientError.storeHomeInvalid
            }

            let home = try ensureDirectory(expectedHome, under: containerRoot, fileManager: fileManager)
            let workingDirectory = try ensureDirectory(
                containerRoot.appendingPathComponent("Working/\(accountID.uuidString)", isDirectory: true),
                under: containerRoot,
                fileManager: fileManager
            )
            let temporaryDirectory = try ensureDirectory(
                containerRoot.appendingPathComponent("Temporary/\(accountID.uuidString)", isDirectory: true),
                under: containerRoot,
                fileManager: fileManager
            )

            return CodexProcessConfiguration(
                environment: [
                    "HOME": home.path,
                    "CODEX_HOME": home.path,
                    "TMPDIR": temporaryDirectory.path,
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                ],
                workingDirectoryURL: workingDirectory
            )
        } catch let error as CodexClientError {
            throw error
        } catch {
            throw CodexClientError.storeHomeInvalid
        }
    }

    private static func ensureDirectory(
        _ directory: URL,
        under containerRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        let expected = directory.standardizedFileURL
        let rootPrefix = containerRoot.path.hasSuffix("/") ? containerRoot.path : containerRoot.path + "/"
        guard expected.path.hasPrefix(rootPrefix) else {
            throw CodexClientError.storeHomeInvalid
        }

        try fileManager.createDirectory(at: expected, withIntermediateDirectories: true)
        let canonical = expected.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == expected.path else {
            throw CodexClientError.storeHomeInvalid
        }
        return canonical
    }
}
