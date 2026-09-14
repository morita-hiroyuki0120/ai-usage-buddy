import Foundation
import Combine
import Testing
@testable import AIUsageBuddy

/// 通知しきい値の即時更新・永続化・5刻み正規化・変更通知のテスト。
@Suite
@MainActor
struct SettingsStoreTests {

    /// 一時コンテナ上に SettingsStore を作る（settings.json は container 直下）。
    private func makeStore() -> (store: SettingsStore, container: URL) {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AIUsageBuddyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return (SettingsStore(containerDirectory: container), container)
    }

    @Test("しきい値1の更新は settings に即座に反映される")
    func updateThreshold1AppliesImmediately() {
        let (store, _) = makeStore()
        #expect(store.settings.notificationThresholds == [20, 10], "初期値は 20% / 10%")

        store.updateNotificationThreshold(at: 0, to: 25)
        #expect(store.settings.notificationThresholds[0] == 25, "更新直後に値が変わる")
        #expect(store.settings.notificationThresholds[1] == 10, "他方は変わらない")
    }

    @Test("しきい値2はしきい値1と独立して更新できる")
    func updateThreshold2Independently() {
        let (store, _) = makeStore()

        store.updateNotificationThreshold(at: 1, to: 15)
        #expect(store.settings.notificationThresholds[0] == 20, "しきい値1は初期値のまま")
        #expect(store.settings.notificationThresholds[1] == 15)
    }

    @Test("更新は settings.json へ保存され、再読込でも値が残る")
    func updatePersistsAndSurvivesReload() throws {
        let (store, container) = makeStore()

        store.updateNotificationThreshold(at: 0, to: 51)
        store.updateNotificationThreshold(at: 1, to: 5)

        // 正規化済みの値がファイルへ保存されている（didSet → persist が走る）
        let data = try Data(contentsOf: container.appendingPathComponent("settings.json"))
        let saved = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(saved.notificationThresholds == [50, 5])

        // 新しい SettingsStore で同じファイルから読み込んでも変更値が残る
        let reloaded = SettingsStore(containerDirectory: container)
        #expect(reloaded.settings.notificationThresholds == [50, 5])
    }

    @Test("しきい値は5〜100の5の倍数へ正規化される")
    func normalizesToNearestLowerMultipleOfFive() {
        let (store, _) = makeStore()

        let cases: [(input: Int, expected: Int)] = [
            (0, 5), (-30, 5), (1, 5), (4, 5), (5, 5), (9, 5),
            (10, 10), (51, 50), (56, 55), (99, 95),
            (100, 100), (101, 100), (999, 100),
        ]
        for testCase in cases {
            store.updateNotificationThreshold(at: 0, to: testCase.input)
            #expect(
                store.settings.notificationThresholds[0] == testCase.expected,
                "\(testCase.input) → \(testCase.expected)"
            )
        }
    }

    @Test("旧設定の5の倍数でない値は読み込み時に正規化されて保存される")
    func migratesLegacyValuesOnLoad() throws {
        let (_, container) = makeStore()

        // 旧バージョン（1〜100の任意値を許していた時代）の settings.json を直接作る
        let legacy = AppSettings(notificationThresholds: [56, 35])
        let legacyData = try JSONEncoder().encode(legacy)
        try legacyData.write(to: container.appendingPathComponent("settings.json"))

        let store = SettingsStore(containerDirectory: container)
        #expect(store.settings.notificationThresholds == [55, 35], "読み込み直後に正規化される")

        // 正規化済みの値が settings.json へ書き戻されている
        let saved = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(contentsOf: container.appendingPathComponent("settings.json"))
        )
        #expect(saved.notificationThresholds == [55, 35])
    }

    @Test("不正な index ではクラッシュせず何も変わらない")
    func invalidIndexIsIgnored() {
        let (store, _) = makeStore()
        let before = store.settings.notificationThresholds

        store.updateNotificationThreshold(at: -1, to: 50)
        store.updateNotificationThreshold(at: 2, to: 50)
        store.updateNotificationThreshold(at: 99, to: 50)

        #expect(store.settings.notificationThresholds == before, "配列は変化しない")
    }

    @Test("更新時に objectWillChange が発生する")
    func updateFiresObjectWillChange() {
        let (store, _) = makeStore()
        var fired = false
        let cancellable = store.objectWillChange.sink { _ in
            fired = true
        }
        defer { _ = cancellable }

        store.updateNotificationThreshold(at: 0, to: 30)
        #expect(fired, "objectWillChange が送られる")

        // 値が変わらない更新（同値）でも setter 経由なので通知は発生する
        fired = false
        store.updateNotificationThreshold(at: 0, to: 30)
        #expect(fired)
    }

    @Test("Stepper相当のonIncrement/onDecrement経路でもクリック1回分が即時反映される")
    func stepperIncrementDecrementRouteUpdatesImmediately() {
        let (store, _) = makeStore()

        // SettingsView の Stepper と同じクロージャ経路（step: 5・範囲 5...100 の5刻み）
        let onIncrement: () -> Void = {
            let current = store.settings.notificationThresholds[0]
            store.updateNotificationThreshold(at: 0, to: min(100, current + 5))
        }
        let onDecrement: () -> Void = {
            let current = store.settings.notificationThresholds[0]
            store.updateNotificationThreshold(at: 0, to: max(5, current - 5))
        }

        #expect(store.settings.notificationThresholds[0] == 20)
        onIncrement()
        #expect(store.settings.notificationThresholds[0] == 25, "上矢印1回分が即時反映")
        onDecrement()
        #expect(store.settings.notificationThresholds[0] == 20, "下矢印1回分も即時反映")

        // 連打してもレンジ外へ出ない（100%で停止・5%で停止して1%へは下がらない）
        for _ in 0..<30 { onIncrement() }
        #expect(store.settings.notificationThresholds[0] == 100, "100%のまま")
        onIncrement()
        #expect(store.settings.notificationThresholds[0] == 100, "100%から上矢印を押しても100%のまま")
        for _ in 0..<30 { onDecrement() }
        #expect(store.settings.notificationThresholds[0] == 5, "5%で停止")
        onDecrement()
        #expect(store.settings.notificationThresholds[0] == 5, "5%から下矢印を押しても1%にならず5%のまま")
    }
}
