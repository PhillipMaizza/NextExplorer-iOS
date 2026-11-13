import CoreModels
import FilesClient
import Foundation

/// The disk behind `LegacyDownloadStore`: `privateRoot/<scope>/` per account, plus a small map of
/// which account owns which scope. `sharedRoots` are the folders older versions saved into.
struct SavedEarlierDisk: Sendable {
    let privateRoot: URL
    let sharedRoots: [URL]

    private static let ownersFileName = "owners.json"
    /// One lock for the owners map: sign in and account removal can run at once.
    private static let ownersLock = NSLock()

    /// `Application Support/SavedEarlier`, excluded from backup; older versions saved into
    /// `Documents/Downloads` (shown in the Files app) and `Caches/Downloads`.
    static var live: SavedEarlierDisk {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return SavedEarlierDisk(
            privateRoot: support.appendingPathComponent("SavedEarlier", isDirectory: true),
            sharedRoots: [
                documents.appendingPathComponent("Downloads", isDirectory: true),
                caches.appendingPathComponent("Downloads", isDirectory: true),
            ]
        )
    }

    /// An account's own folder. A scope is a hash in hex, never a path, so it cannot point elsewhere.
    private func folder(for scope: String) -> URL? {
        guard SafeFileName.isSafeComponent(scope), !scope.isEmpty else { return nil }
        return privateRoot.appendingPathComponent(scope, isDirectory: true)
    }

    private func createPrivateFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var root = privateRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        FileProtection.apply(to: [privateRoot, url])
    }

    func save(_ sourceURL: URL, fileName: String, scope: String) throws -> URL {
        // Without an account the copy would belong to no one.
        guard let folder = folder(for: scope) else { throw CocoaError(.fileWriteNoPermission) }
        try createPrivateFolder(folder)
        // `fileName` comes from the server: keep a hostile `../` inside the folder.
        let destination = Self.availableDestination(in: folder, fileName: SafeFileName.component(fileName))
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        FileProtection.apply(to: destination)
        return destination
    }

    func list(scope: String) throws -> [LocalDownload] {
        guard let folder = folder(for: scope) else { return [] }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else { return [] }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        return try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { return nil }
            return LocalDownload(
                url: url,
                fileName: url.lastPathComponent,
                size: Int64(values.fileSize ?? 0),
                modifiedDate: values.contentModificationDate ?? .distantPast
            )
        }
    }

    static func rename(_ url: URL, to newName: String) throws -> URL {
        // A rename must stay a rename: a typed name carrying a path can't move the file out.
        guard SafeFileName.isSafeComponent(newName) else { throw CocoaError(.fileWriteInvalidFileName) }
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard destination != url else { return url }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        FileProtection.apply(to: destination)
        return destination
    }

    // MARK: Owners

    private var ownersURL: URL {
        privateRoot.appendingPathComponent(Self.ownersFileName)
    }

    private func readOwners() -> [String: String] {
        guard let data = try? Data(contentsOf: ownersURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func writeOwners(_ owners: [String: String]) {
        guard let data = try? JSONEncoder().encode(owners) else { return }
        try? createPrivateFolder(privateRoot)
        try? data.write(to: ownersURL, options: .atomic)
        FileProtection.apply(to: ownersURL)
    }

    func recordOwner(accountID: String, scope: String) {
        guard folder(for: scope) != nil else { return }
        Self.ownersLock.withLock {
            var owners = readOwners()
            guard owners[accountID] != scope else { return }
            owners[accountID] = scope
            writeOwners(owners)
        }
    }

    func ownerScope(accountID: String) -> String? {
        Self.ownersLock.withLock { readOwners()[accountID] }
    }

    func removeAccount(_ accountID: String) {
        Self.ownersLock.withLock {
            var owners = readOwners()
            guard let scope = owners.removeValue(forKey: accountID) else { return }
            if let folder = folder(for: scope) {
                try? FileManager.default.removeItem(at: folder)
            }
            writeOwners(owners)
        }
    }

    func removeAll() {
        Self.ownersLock.withLock {
            try? FileManager.default.removeItem(at: privateRoot)
        }
    }

    // MARK: Moving out of the shared folders

    /// Idempotent: after the first run the shared folders are gone, and later runs only check that.
    func moveSharedFilesToPrivateStorage() {
        let fileManager = FileManager.default
        for sharedRoot in sharedRoots where fileManager.fileExists(atPath: sharedRoot.path) {
            let entries = (try? fileManager.contentsOfDirectory(
                at: sharedRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )) ?? []
            for entry in entries {
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                // An account's folder is named by its scope; anything else has no known owner.
                if isDirectory, Self.isScope(entry.lastPathComponent),
                   let folder = folder(for: entry.lastPathComponent)
                {
                    moveFiles(from: entry, into: folder)
                }
                try? fileManager.removeItem(at: entry)
            }
            try? fileManager.removeItem(at: sharedRoot)
        }
    }

    private func moveFiles(from source: URL, into folder: URL) {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        guard !files.isEmpty, (try? createPrivateFolder(folder)) != nil else { return }
        for file in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            try? fileManager.moveItem(
                at: file,
                to: Self.availableDestination(in: folder, fileName: file.lastPathComponent)
            )
        }
    }

    /// `DownloadAccountScope.identifier`: 32 lowercase hex characters.
    static func isScope(_ name: String) -> Bool {
        name.count == 32 && name.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// The first free URL in `directory` for `fileName`: the name itself if unused, otherwise with
    /// a " (1)", " (2)", ... suffix before the extension, so two files sharing a name both survive.
    static func availableDestination(in directory: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        let candidate = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 1
        while true {
            let suffixed = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let url = directory.appendingPathComponent(suffixed)
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            index += 1
        }
    }
}
