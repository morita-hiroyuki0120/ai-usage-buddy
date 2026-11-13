import SwiftUI
import AppKit

/// Store 版のデバイスコードログイン進行表示。
/// ワンタイムコード（等幅・大）、コピー、ブラウザを開く、キャンセルを提供する。
struct DeviceCodeLoginView: View {
    @ObservedObject var model: AppModel
    let userCode: String
    let verificationURL: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("login.deviceCode.instruction"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(userCode)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel(L("login.deviceCode.codeLabel"))
                .accessibilityValue(userCode)
            HStack {
                Button(copied ? L("login.deviceCode.copied") : L("login.deviceCode.copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    copied = true
                }
                Button(L("login.deviceCode.openBrowser")) {
                    if let url = URL(string: verificationURL) { NSWorkspace.shared.open(url) }
                }
                Button(L("settings.login.cancel")) {
                    Task { await model.cancelLogin() }
                }
            }
            Text(L("login.deviceCode.waiting"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
