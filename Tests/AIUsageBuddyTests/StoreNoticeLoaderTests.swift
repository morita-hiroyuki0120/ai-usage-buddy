import Darwin
import Foundation
import Testing
@testable import AIUsageBuddy

@Suite
struct StoreNoticeLoaderTests {
    private struct Fixture {
        let root: URL
        let bundle: URL
        let notices: URL

        init() throws {
            // Foundation may abbreviate /private/var back to the /var symlink.
            let canonical = try #require(realpath(FileManager.default.temporaryDirectory.path, nil))
            defer { free(canonical) }
            root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
                .appendingPathComponent("StoreNoticeTests-\(UUID().uuidString)")
            bundle = root.appendingPathComponent("Fixture.app")
            notices = bundle.appendingPathComponent("Contents/Resources/StoreNotices")
            try FileManager.default.createDirectory(at: notices, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
        func write(_ data: Data, document: StoreNoticeDocument = .appLicense) throws {
            try data.write(to: notices.appendingPathComponent(document.rawValue))
        }
    }

    @Test func allowlistRejectsOtherNames() {
        #expect(Set(StoreNoticeDocument.allCases.map(\.rawValue)) ==
            Set(["App-LICENSE", "LICENSE", "NOTICE", "THIRD-PARTY-NOTICES.txt", "SOURCE-AVAILABILITY.txt"]))
        for name in ["../LICENSE", "/tmp/LICENSE", "packaging-receipt.json", "SOURCE-AVAILABILITY.draft.txt", "https://example.com/LICENSE"] {
            #expect(StoreNoticeDocument(rawValue: name) == nil)
        }
    }

    @Test(arguments: StoreNoticeDocument.allCases)
    func readsOnlyInjectedBundle(_ document: StoreNoticeDocument) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let text = "日本語 license <sample>\n\(document.rawValue)"
        try fixture.write(Data(text.utf8), document: document)
        #expect(StoreNoticeLoader(bundleURL: fixture.bundle).read(document) == .text(text))
        #expect(StoreNoticeLoader(bundleURL: fixture.root.appendingPathComponent("Other.app")).read(document) == .unavailable)
    }

    @Test func missingDoesNotUseSiblingOrDraft() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data("must not appear".utf8).write(to: fixture.root.appendingPathComponent("App-LICENSE"))
        try Data("draft".utf8).write(to: fixture.notices.appendingPathComponent("SOURCE-AVAILABILITY.draft.txt"))
        for document in StoreNoticeDocument.allCases {
            #expect(StoreNoticeLoader(bundleURL: fixture.bundle).read(document) == .unavailable)
        }
        try FileManager.default.removeItem(at: fixture.notices)
        #expect(StoreNoticeLoader(bundleURL: fixture.bundle).read(.appLicense) == .unavailable)
    }

    @Test func rejectsInvalidUTF8EmptyAndOversize() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let loader = StoreNoticeLoader(bundleURL: fixture.bundle, byteLimit: 4)
        for data in [Data(), Data([0xff, 0xfe]), Data(repeating: 65, count: 5)] {
            try fixture.write(data)
            #expect(loader.read(.appLicense) == .unavailable)
        }
        try fixture.write(Data("abcd".utf8))
        #expect(loader.read(.appLicense) == .text("abcd"))
        #expect(StoreNoticeLoader(bundleURL: fixture.bundle, byteLimit: 0).read(.appLicense) == .unavailable)
        #expect(StoreNoticeLoader(bundleURL: fixture.bundle, byteLimit: StoreNoticeLoader.maximumBytes + 1).read(.appLicense) == .unavailable)
        let remote = try #require(URL(string: "https://example.com/Fixture.app"))
        #expect(StoreNoticeLoader(bundleURL: remote).read(.appLicense) == .unavailable)
    }

    @Test(arguments: ["", "Contents", "Contents/Resources", "Contents/Resources/StoreNotices", "Contents/Resources/StoreNotices/App-LICENSE"])
    func rejectsSymlinksAtEveryComponent(_ component: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try fixture.write(Data("outside contents".utf8))
        let target = component.isEmpty ? fixture.bundle : fixture.bundle.appendingPathComponent(component)
        let outside = fixture.root.appendingPathComponent("Outside")
        try FileManager.default.moveItem(at: target, to: outside)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        #expect(StoreNoticeLoader(bundleURL: fixture.bundle).read(.appLicense) == .unavailable)
    }

    @Test func rejectsDirectoryAsDocument() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.notices.appendingPathComponent("App-LICENSE"), withIntermediateDirectories: false)
        #expect(StoreNoticeLoader(bundleURL: fixture.bundle).read(.appLicense) == .unavailable)
    }

    @Test @MainActor func noticeLabelsAreLocalized() {
        let suite = "StoreNoticeLabels-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = LocalizationManager(defaults: defaults)
        let keys = StoreNoticeDocument.allCases.map(\.titleKey) +
            ["settings.notices.title", "settings.notices.hint", "settings.notices.document",
             "settings.notices.unavailable", "settings.notices.loading", "settings.notices.close"]
        for key in keys {
            for language in AppLanguage.allCases {
                #expect(manager.string(key: key, language: language) != key)
            }
        }
    }
}
