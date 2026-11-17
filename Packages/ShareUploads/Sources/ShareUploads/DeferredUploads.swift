import Foundation

/// A shared file too big to send as one request through a typical proxy, kept whole in the App
/// Group until the app uploads it in pieces.
public struct DeferredUpload: Equatable, Sendable {
    public let id: String
    public let accountID: String
    /// Where the file's bytes are now: the destination folder the claim moved them to.
    public let fileURL: URL
    public let fileName: String
    public let destination: String

    public init(id: String, accountID: String, fileURL: URL, fileName: String, destination: String) {
        self.id = id
        self.accountID = accountID
        self.fileURL = fileURL
        self.fileName = fileName
        self.destination = destination
    }
}

/// The files the Share Extension leaves for the app. A background session cannot send a file in
/// resumable pieces, and a proxy such as Cloudflare refuses one request over about 100 MB, so a
/// big file is copied here untouched and the app, which already uploads in pieces, finishes it.
///
/// Each file is its own folder (`<id>/payload` plus `<id>/meta.json`) written under a dot name and
/// renamed when complete, so a claim never sees a half written one. A claim moves the payload out
/// and removes the folder, so two claims never both get a file.
public struct DeferredUploads: Sendable {
    /// Just under the 100 MB a Cloudflare tunnel accepts, so anything over it goes in pieces.
    public static let thresholdBytes: Int64 = 90 * 1024 * 1024

    private struct Meta: Codable {
        var accountID: String
        var fileName: String
        var destination: String
    }

    private enum Constants {
        static let folderName = "DeferredUploads"
        static let payload = "payload"
        static let metaFile = "meta.json"
        static let partialPrefix = "."
        static let partialAge: TimeInterval = 60 * 60
    }

    let root: URL

    /// `nil` when this build has no App Group to share through.
    public static let live: DeferredUploads? = AppGroup.containerURL.map {
        DeferredUploads(root: $0.appendingPathComponent(Constants.folderName, isDirectory: true))
    }

    /// Copies `fileURL` in and returns the folder that now holds it.
    func stage(copying fileURL: URL, fileName: String, accountID: String, destination: String) throws -> URL {
        let id = UUID().uuidString
        let partial = root.appendingPathComponent(Constants.partialPrefix + id, isDirectory: true)
        let folder = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: fileURL, to: partial.appendingPathComponent(Constants.payload))
            let meta = Meta(accountID: accountID, fileName: fileName, destination: destination)
            try JSONEncoder().encode(meta).write(to: partial.appendingPathComponent(Constants.metaFile))
            try FileManager.default.moveItem(at: partial, to: folder)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        return folder
    }

    /// Moves `accountID`'s files into `directory` and returns them. Another account's files stay
    /// where they are: they only ever upload as the account that shared them.
    public func claim(accountID: String, into directory: URL) -> [DeferredUpload] {
        var claimed: [DeferredUpload] = []
        for folder in folders() {
            guard
                let data = try? Data(contentsOf: folder.appendingPathComponent(Constants.metaFile)),
                let meta = try? JSONDecoder().decode(Meta.self, from: data),
                meta.accountID == accountID
            else { continue }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = folder.lastPathComponent
            let target = directory.appendingPathComponent(id)
            do {
                try FileManager.default.moveItem(at: folder.appendingPathComponent(Constants.payload), to: target)
            } catch {
                continue
            }
            try? FileManager.default.removeItem(at: folder)
            // App Group contents are untrusted: a name can never reach outside the destination folder.
            claimed.append(DeferredUpload(
                id: id, accountID: accountID, fileURL: target, fileName: meta.fileName.lastPathComponentOnly,
                destination: meta.destination
            ))
        }
        return claimed
    }

    /// Signing out: deletes the files of every account not in `accountIDs`, and any half written
    /// folder an hour old (a younger one may still be filling in the extension).
    public func discard(keepingAccounts accountIDs: Set<String>, now: Date = Date()) {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in all {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            if name.hasPrefix(Constants.partialPrefix) {
                let touched = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let touched, now.timeIntervalSince(touched) > Constants.partialAge {
                    try? FileManager.default.removeItem(at: folder)
                }
                continue
            }
            let data = try? Data(contentsOf: folder.appendingPathComponent(Constants.metaFile))
            let meta = data.flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
            if let meta, accountIDs.contains(meta.accountID) {
                continue
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    public var isEmpty: Bool {
        folders().isEmpty
    }

    private func folders() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { !$0.hasPrefix(Constants.partialPrefix) }
            .map { root.appendingPathComponent($0, isDirectory: true) }
    }
}

private extension String {
    var lastPathComponentOnly: String {
        (self as NSString).lastPathComponent
    }
}
