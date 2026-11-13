import ComposableArchitecture
import CoreModels
import Foundation

/// One file an earlier version saved into the app, listed under "Saved earlier" in the Offline
/// tab. Deleting it here only removes this local copy: it never touches the server, unlike every
/// other delete action in the app.
public struct LocalDownload: Equatable, Identifiable, Sendable {
    public let url: URL
    public let fileName: String
    public let size: Int64
    public let modifiedDate: Date

    public var id: String {
        url.path
    }

    public init(url: URL, fileName: String, size: Int64, modifiedDate: Date) {
        self.url = url
        self.fileName = fileName
        self.size = size
        self.modifiedDate = modifiedDate
    }
}

/// The files earlier versions saved into the app, kept per account in private storage (hidden
/// from the Files app) and removed with the account, like files kept offline. `scope` is the
/// account's `DownloadAccountScope.identifier`; an empty scope (no account) saves and lists nothing.
public struct LegacyDownloadStore: Sendable {
    public var save: @Sendable (_ sourceURL: URL, _ fileName: String, _ scope: String) throws -> URL
    public var list: @Sendable (_ scope: String) throws -> [LocalDownload]
    public var delete: @Sendable (_ url: URL) throws -> Void
    /// Renames the local copy in place (same folder), returning its new URL. Local only, like
    /// `delete`: the server file is never touched.
    public var rename: @Sendable (_ url: URL, _ newName: String) throws -> URL
    /// Remembers which account a scope belongs to, so removing the account finds its files.
    public var recordOwner: @Sendable (_ accountID: String, _ scope: String) -> Void
    /// The folder recorded for an account, so a launch without a connection (no user id yet) still
    /// lists the account's own files; nil for an account never recorded.
    public var ownerScope: @Sendable (_ accountID: String) -> String?
    /// Removes the files of one account, when it signs out or its session expires.
    public var removeAccount: @Sendable (_ accountID: String) -> Void
    /// Removes every account's files, when the last account signs out.
    public var removeAll: @Sendable () -> Void
    /// Moves what older versions saved in the shared, Files app visible folders into private
    /// storage. Each account's folder keeps its owner; files saved before accounts had their own
    /// folder have no known owner and are deleted, so no account can claim them.
    public var moveSharedFilesToPrivateStorage: @Sendable () -> Void

    public init(
        save: @escaping @Sendable (_ sourceURL: URL, _ fileName: String, _ scope: String) throws -> URL,
        list: @escaping @Sendable (_ scope: String) throws -> [LocalDownload],
        delete: @escaping @Sendable (_ url: URL) throws -> Void,
        rename: @escaping @Sendable (_ url: URL, _ newName: String) throws -> URL,
        recordOwner: @escaping @Sendable (_ accountID: String, _ scope: String) -> Void = { _, _ in },
        ownerScope: @escaping @Sendable (_ accountID: String) -> String? = { _ in nil },
        removeAccount: @escaping @Sendable (_ accountID: String) -> Void = { _ in },
        removeAll: @escaping @Sendable () -> Void = {},
        moveSharedFilesToPrivateStorage: @escaping @Sendable () -> Void = {}
    ) {
        self.save = save
        self.list = list
        self.delete = delete
        self.rename = rename
        self.recordOwner = recordOwner
        self.ownerScope = ownerScope
        self.removeAccount = removeAccount
        self.removeAll = removeAll
        self.moveSharedFilesToPrivateStorage = moveSharedFilesToPrivateStorage
    }
}

extension LegacyDownloadStore: DependencyKey {
    /// A store over `disk`; tests pass temporary folders.
    static func onDisk(_ disk: SavedEarlierDisk) -> LegacyDownloadStore {
        LegacyDownloadStore(
            save: { try disk.save($0, fileName: $1, scope: $2) },
            list: { try disk.list(scope: $0) },
            delete: { try FileManager.default.removeItem(at: $0) },
            rename: { try SavedEarlierDisk.rename($0, to: $1) },
            recordOwner: { disk.recordOwner(accountID: $0, scope: $1) },
            ownerScope: { disk.ownerScope(accountID: $0) },
            removeAccount: { disk.removeAccount($0) },
            removeAll: { disk.removeAll() },
            moveSharedFilesToPrivateStorage: { disk.moveSharedFilesToPrivateStorage() }
        )
    }

    public static let liveValue = onDisk(.live)

    public static let testValue = LegacyDownloadStore(
        save: { _, _, _ in throw Unimplemented() },
        list: { _ in throw Unimplemented() },
        delete: { _ in throw Unimplemented() },
        rename: { _, _ in throw Unimplemented() }
    )

    private struct Unimplemented: Error {}
}

public extension DependencyValues {
    var localDownloadStore: LegacyDownloadStore {
        get { self[LegacyDownloadStore.self] }
        set { self[LegacyDownloadStore.self] = newValue }
    }
}
