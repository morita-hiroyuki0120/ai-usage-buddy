import Darwin
import Foundation

/// Must match StorePackaging/prepare.py PAYLOADS. No caller-supplied filenames.
enum StoreNoticeDocument: String, CaseIterable, Identifiable, Sendable {
    case appLicense = "App-LICENSE"
    case helperLicense = "LICENSE"
    case helperNotice = "NOTICE"
    case thirdPartyNotices = "THIRD-PARTY-NOTICES.txt"
    case sourceAvailability = "SOURCE-AVAILABILITY.txt"

    var id: String { rawValue }
    var titleKey: String { "settings.notices." + String(describing: self) }
}

enum StoreNoticeContent: Equatable, Sendable {
    case text(String)
    case unavailable
}

/// Reads only the five packaged resources. Descriptor-relative opens reject links
/// at every path component, including the injected bundle URL's ancestors.
struct StoreNoticeLoader: Sendable {
    static let maximumBytes = 16 * 1024 * 1024
    let bundleURL: URL
    let byteLimit: Int

    init(bundleURL: URL = Bundle.main.bundleURL, byteLimit: Int = maximumBytes) {
        self.bundleURL = bundleURL
        self.byteLimit = byteLimit
    }

    func read(_ document: StoreNoticeDocument) -> StoreNoticeContent {
        guard bundleURL.isFileURL, bundleURL.host == nil || bundleURL.host == "",
              (1...Self.maximumBytes).contains(byteLimit),
              !bundleURL.pathComponents.contains("..") else { return .unavailable }
        var directory = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { return .unavailable }
        defer { Darwin.close(directory) }
        let components = bundleURL.pathComponents.filter { $0 != "/" }
            + ["Contents", "Resources", "StoreNotices"]
        for component in components {
            let next = component.withCString {
                openat(directory, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard next >= 0 else { return .unavailable }
            Darwin.close(directory)
            directory = next
        }
        let file = document.rawValue.withCString {
            openat(directory, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard file >= 0 else { return .unavailable }
        defer { Darwin.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= Int64(byteLimit) else { return .unavailable }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        do {
            var data = Data()
            while let chunk = try handle.read(upToCount: min(64 * 1024, byteLimit + 1 - data.count)),
                  !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= byteLimit else { return .unavailable }
            }
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return .unavailable
            }
            return .text(text)
        } catch {
            return .unavailable
        }
    }
}
