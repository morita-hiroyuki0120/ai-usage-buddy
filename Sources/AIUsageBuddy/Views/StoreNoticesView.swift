#if AI_USAGE_BUDDY_APP_STORE
import SwiftUI

struct StoreNoticesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var selection = StoreNoticeDocument.appLicense
    @State private var content: StoreNoticeContent?
    private let loader = StoreNoticeLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("settings.notices.title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker(L("settings.notices.document"), selection: $selection) {
                ForEach(StoreNoticeDocument.allCases) { document in
                    Text(L(document.titleKey)).tag(document)
                }
            }
            .accessibilityLabel(L("settings.notices.document"))
            Group {
                switch content {
                case .text(let text):
                    ScrollView {
                        Text(verbatim: text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                case .unavailable:
                    Text(L("settings.notices.unavailable"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case nil:
                    ProgressView(L("settings.notices.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Spacer()
                Button(L("settings.notices.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
        .task(id: selection) {
            content = nil
            let document = selection
            let reader = loader
            let result = await Task.detached(priority: .userInitiated) {
                reader.read(document)
            }.value
            guard !Task.isCancelled, selection == document else { return }
            content = result
        }
    }
}
#endif
