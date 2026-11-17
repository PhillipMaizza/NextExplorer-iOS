import CoreModels
import Foundation

/// A shared file too big to send as one request through a typical proxy, kept whole in the App
/// Group until the app uploads it in pieces.
public struct DeferredUpload: Equatable, Sendable {
    public let id: String
    public let accountID: String
    /// Where the file's bytes are, inside the App Group.
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
/// renamed when complete, so a reader never sees a half written one.
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
        /// A kept file that never uploaded (a destination that is gone, a refused account) is dropped after this.
        static let retention: TimeInterval = 7 * 24 * 60 * 60
    }

    private static let limitKeyPrefix = "shareUploads.directLimitBytes."

    let root: URL

    /// The size above which a file for `serverURL` is kept for the app: the fixed limit, lowered to
    /// half of the smallest file this origin's proxy has refused (a self hosted proxy may cap lower
    /// than a Cloudflare tunnel), never below what a proxy cuts off anyway.
    static func directLimitBytes(for serverURL: URL, defaults: UserDefaults) -> Int64 {
        let learned = Int64(defaults.integer(forKey: limitKey(serverURL)))
        return learned > 0 ? min(thresholdBytes, learned) : thresholdBytes
    }

    /// A direct upload of `bytes` was refused as too large: files over half that size are kept for
    /// the app from now on.
    static func learnRefusal(ofBytes bytes: Int64, serverURL: URL, defaults: UserDefaults) {
        // A small file refused says nothing about size (a firewall rule, say): lowering the limit to the
        // floor for it would send every big file through the app for good.
        guard bytes > Int64(UploadMode.largeFileBytes) else { return }
        let learned = max(Int64(UploadMode.largeFileBytes), bytes / 2)
        let known = directLimitBytes(for: serverURL, defaults: defaults)
        defaults.set(Int(min(known, learned)), forKey: limitKey(serverURL))
    }

    private static func limitKey(_ serverURL: URL) -> String {
        let origin = [serverURL.host, serverURL.port.map(String.init)].compactMap(\.self).joined(separator: ":")
        return limitKeyPrefix + origin
    }

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

    /// `accountID`'s waiting files, where they are: the app uploads them in place, so one that was
    /// cut off by a force quit is simply found again at the next launch. Another account's files
    /// stay untouched: they only ever upload as the account that shared them. A folder whose file
    /// is gone (uploaded or cancelled), or a week old, is removed.
    public func pending(accountID: String, now: Date = Date()) -> [DeferredUpload] {
        var found: [DeferredUpload] = []
        for folder in folders() {
            guard
                let data = try? Data(contentsOf: folder.appendingPathComponent(Constants.metaFile)),
                let meta = try? JSONDecoder().decode(Meta.self, from: data),
                meta.accountID == accountID
            else { continue }
            let payload = folder.appendingPathComponent(Constants.payload)
            let stagedAt = (try? folder.appendingPathComponent(Constants.metaFile)
                .resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let isExpired = stagedAt.map { now.timeIntervalSince($0) > Constants.retention } ?? false
            guard !isExpired, FileManager.default.fileExists(atPath: payload.path) else {
                try? FileManager.default.removeItem(at: folder)
                continue
            }
            // App Group contents are untrusted: a name can never reach outside the destination folder.
            found.append(DeferredUpload(
                id: folder.lastPathComponent, accountID: accountID, fileURL: payload,
                fileName: (meta.fileName as NSString).lastPathComponent, destination: meta.destination
            ))
        }
        return found
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
