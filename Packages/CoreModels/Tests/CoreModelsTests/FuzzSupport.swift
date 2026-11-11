import Foundation

/// Deterministic RNG (SplitMix64) for the monkey tests, so a fuzz failure reproduces on rerun.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Hostile strings: path separators, whitespace, control bytes, unicode and emoji.
enum FuzzStrings {
    private static let alphabet: [Character] = Array(
        "abcXYZ0123./\\:@-_ !#?%&=+[]().," + "\u{0}\n\t" + "éñ🙂🔥"
    )

    static func random(using rng: inout SplitMix64, maxLength: Int) -> String {
        let length = Int(rng.next() % UInt64(maxLength + 1))
        var out = ""
        out.reserveCapacity(length)
        for _ in 0 ..< length {
            out.append(alphabet[Int(rng.next() % UInt64(alphabet.count))])
        }
        return out
    }
}
