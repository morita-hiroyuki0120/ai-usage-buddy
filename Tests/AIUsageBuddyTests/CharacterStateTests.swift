import Testing
@testable import AIUsageBuddy

/// 状態判定（0, 1, 29, 30, 69, 70, 100%）とヒステリシスのテスト。
@Suite
struct CharacterStateTests {

    let machine = CharacterStateMachine()

    // MARK: - バンド判定

    @Test("バンド境界: 0,1,29,30,69,70,100")
    func bandBoundaries() {
        #expect(CharacterStateMachine.band(forPercent: 0) == .sleeping, "0%は睡眠")
        #expect(CharacterStateMachine.band(forPercent: 1) == .tired, "1%は疲労")
        #expect(CharacterStateMachine.band(forPercent: 29) == .tired, "29%は疲労")
        #expect(CharacterStateMachine.band(forPercent: 30) == .normal, "30%は通常")
        #expect(CharacterStateMachine.band(forPercent: 69) == .normal, "69%は通常")
        #expect(CharacterStateMachine.band(forPercent: 70) == .energetic, "70%は元気")
        #expect(CharacterStateMachine.band(forPercent: 100) == .energetic, "100%は元気")
    }

    // MARK: - 未取得

    @Test("データ未取得は unknown へ")
    func noDataGoesUnknown() {
        #expect(machine.next(current: .energetic, percent: nil) == .unknown)
        #expect(machine.next(current: .normal, percent: nil) == .unknown)
    }

    @Test("unknown からの復帰はバンドから直接")
    func unknownRecoversViaBand() {
        #expect(machine.next(current: .unknown, percent: 80) == .energetic)
        #expect(machine.next(current: .unknown, percent: 50) == .normal)
        #expect(machine.next(current: .unknown, percent: 10) == .tired)
        #expect(machine.next(current: .unknown, percent: 0) == .sleeping)
    }

    // MARK: - ヒステリシス

    @Test("元気→通常は65%未満")
    func energeticToNormalBelow65() {
        #expect(machine.next(current: .energetic, percent: 64) == .normal)
        #expect(machine.next(current: .energetic, percent: 65) == .energetic, "65ちょうどでは元気のまま")
        #expect(machine.next(current: .energetic, percent: 66) == .energetic, "65〜69は元気のまま（ヒステリシス帯）")
    }

    @Test("通常→元気は70%以上")
    func normalToEnergeticAt70OrAbove() {
        #expect(machine.next(current: .normal, percent: 69) == .normal, "69では通常のまま")
        #expect(machine.next(current: .normal, percent: 70) == .energetic, "70以上で元気へ")
        #expect(machine.next(current: .normal, percent: 100) == .energetic)
    }

    @Test("通常→疲労は29%以下")
    func normalToTiredAt29OrBelow() {
        #expect(machine.next(current: .normal, percent: 29) == .tired, "29%以下で疲労へ")
        #expect(machine.next(current: .normal, percent: 30) == .normal, "30では通常のまま")
    }

    @Test("疲労→通常は34%以上")
    func tiredToNormalAt34OrAbove() {
        #expect(machine.next(current: .tired, percent: 33) == .tired, "33では疲労のまま")
        #expect(machine.next(current: .tired, percent: 34) == .normal, "34以上で通常へ")
    }

    @Test("疲労→睡眠は0%")
    func tiredToSleepingAtZero() {
        #expect(machine.next(current: .tired, percent: 0) == .sleeping, "0%で睡眠へ")
        #expect(machine.next(current: .tired, percent: 1) == .tired, "1%では疲労のまま")
    }

    @Test("睡眠→疲労は5%以上")
    func sleepingToTiredAt5OrAbove() {
        #expect(machine.next(current: .sleeping, percent: 4) == .sleeping, "4%では睡眠のまま")
        #expect(machine.next(current: .sleeping, percent: 5) == .tired, "5%以上で疲労へ")
    }

    // MARK: - 急変時の段階的遷移

    @Test("急落は段階的に睡眠へ到達する")
    func largeDropStepsThroughBands() {
        #expect(machine.next(current: .energetic, percent: 0) == .sleeping)
    }

    @Test("急上昇は段階的に元気へ到達する")
    func largeRiseStepsThroughBands() {
        #expect(machine.next(current: .sleeping, percent: 100) == .energetic)
    }

    // MARK: - 連続遷移の安定性

    @Test("緩やかな低下で最終的に通常へ")
    func displayedPercentDrivesState() {
        var state = CharacterStateMachine.band(forPercent: 85)
        for percent in [80, 72, 70, 68, 66, 65, 64] {
            state = machine.next(current: state, percent: percent)
        }
        #expect(state == .normal)
    }
}
