import Foundation
import Testing
@testable import AIUsageBuddy

@Suite
struct DeviceCodeLoginTests {

    @Test("chatgptDeviceCodeレスポンスをデコードできる")
    func decodesDeviceCodeResponse() throws {
        let json = #"{"type":"chatgptDeviceCode","loginId":"abc","verificationUrl":"https://auth.openai.com/codex/device","userCode":"ABCD-EFGH"}"#
        let result = try JSONDecoder().decode(LoginStartResult.self, from: Data(json.utf8))
        #expect(result.type == "chatgptDeviceCode")
        #expect(result.loginId == "abc")
        #expect(result.verificationUrl == "https://auth.openai.com/codex/device")
        #expect(result.userCode == "ABCD-EFGH")
        #expect(result.authUrl == nil)
    }

    @Test("従来のchatgptレスポンスも引き続きデコードできる")
    func decodesBrowserResponse() throws {
        let json = #"{"type":"chatgpt","loginId":"abc","authUrl":"https://auth.example/x"}"#
        let result = try JSONDecoder().decode(LoginStartResult.self, from: Data(json.utf8))
        #expect(result.authUrl == "https://auth.example/x")
        #expect(result.userCode == nil)
    }

    @Test("配布チャネルごとにRPC typeが決まる")
    func rpcTypePerChannel() {
        #expect(LoginMethod.method(for: .appStore) == .deviceCode)
        #expect(LoginMethod.method(for: .direct) == .browser)
        #expect(LoginMethod.deviceCode.rpcType == "chatgptDeviceCode")
        #expect(LoginMethod.browser.rpcType == "chatgpt")
    }

    @Test("LogRedactorはuser codeをログから除去する")
    func redactsUserCode() {
        for input in ["userCode: ABCD-EFGH", "userCode=ABCD-EFGH", "\"userCode\":\"ABCD-EFGH\"", "user code ABCD-EFGH"] {
            let scrubbed = LogRedactor.scrub(input)
            #expect(!scrubbed.contains("ABCD-EFGH"), "\(input) -> \(scrubbed)")
        }
    }
}
