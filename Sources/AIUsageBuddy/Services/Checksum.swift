import CryptoKit
import Foundation

/// SHA-256チェックサム生成（配布物の検証用）。
/// `scripts/package-release.sh` が出力する SHA256SUMS.txt と同じ形式（小文字hex・128文字）。
public enum Checksum {

    /// データからSHA-256ダイジェストを小文字hex（64文字）で返す。
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// ファイル内容からSHA-256ダイジェストを小文字hexで返す。
    public static func sha256Hex(contentsOf url: URL) throws -> String {
        try sha256Hex(Data(contentsOf: url))
    }
}
