import Foundation

/// The protection class every file the app keeps for an account carries: encrypted at rest, and
/// readable by a transfer that began before the device locked. Set on each file explicitly, because
/// a file written by `Data.write` or moved in from `tmp` does not reliably take its folder's class.
public enum FileProtection {
    public static func apply(to urls: [URL]) {
        for url in urls {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: url.path
            )
        }
    }

    public static func apply(to url: URL) {
        apply(to: [url])
    }
}
