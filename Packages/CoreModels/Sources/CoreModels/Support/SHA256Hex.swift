import CryptoKit
import Foundation

public extension String {
    /// The SHA256 digest of this string's UTF8 bytes as lowercase hex, the form every cache uses to
    /// name its files. `byteCount` keeps only the first bytes of the digest when a shorter name is enough.
    func sha256Hex(byteCount: Int = SHA256.byteCount) -> String {
        SHA256.hash(data: Data(utf8)).prefix(byteCount).map { String(format: "%02x", $0) }.joined()
    }
}
