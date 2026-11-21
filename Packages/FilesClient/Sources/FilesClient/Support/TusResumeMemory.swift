import CoreModels
import CryptoKit
import Foundation

public enum UploadResumeLinks {
    public static func forgetAll(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(TusResumeMemory.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

struct TusResumeMemory {
    static let keyPrefix = "tusUploadURL."
    private static let sampleBytes = 1_048_576
    private let key: String
    private let defaults: UserDefaults

    init(
        serverURL: URL,
        scope: String,
        destination: String,
        fileName: String,
        fingerprint: String,
        defaults: UserDefaults = .standard
    ) {
        key = Self.keyPrefix + [scope, serverURL.absoluteString, destination, fileName, fingerprint]
            .joined(separator: "|").sha256Hex()
        self.defaults = defaults
    }

    var uploadURL: URL? {
        get { defaults.string(forKey: key).flatMap(URL.init(string:)) }
        nonmutating set { defaults.set(newValue?.absoluteString, forKey: key) }
    }

    static func fingerprint(of fileURL: URL, size: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        hasher.update(data: Data(String(size).utf8))
        try hasher.update(data: handle.read(upToCount: sampleBytes) ?? Data())
        if size > sampleBytes {
            try handle.seek(toOffset: UInt64(max(sampleBytes, size - sampleBytes)))
            try hasher.update(data: handle.read(upToCount: sampleBytes) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
