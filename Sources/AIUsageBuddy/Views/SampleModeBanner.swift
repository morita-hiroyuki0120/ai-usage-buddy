import SwiftUI

/// サンプルデータ表示中であることを示すバナー（シナリオ切替と終了ボタン付き）。
/// 利用枠の数値が出る場所（ポップオーバー／クイック利用状況／設定）に必ず置く。
struct SampleModeBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("sample.banner.title"))
                        .font(.caption.weight(.semibold))
                    Text(L("sample.banner.note"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "flask")
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 8) {
                Picker(L("sample.scenario.label"), selection: Binding(
                    get: { model.sampleScenario ?? .plenty },
                    set: { model.setSampleScenario($0) }
                )) {
                    ForEach(SampleScenario.allCases, id: \.self) { scenario in
                        Text(L(scenario.localizedNameKey)).tag(scenario)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                Spacer()
                Button(L("sample.exit")) {
                    model.exitSampleMode()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1)))
        .accessibilityElement(children: .contain)
    }
}
