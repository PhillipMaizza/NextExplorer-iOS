@testable import CoreModels
import Testing

struct SHA256HexTests {
    /// The standard SHA256 test vector for "abc": cache file names on disk depend on this exact form.
    @Test("cache file names: the digest is lowercase hex, whole or cut to its first bytes")
    func digestIsLowercaseHex() {
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect("abc".sha256Hex() == abc)
        #expect("abc".sha256Hex(byteCount: 4) == String(abc.prefix(8)))
    }
}
