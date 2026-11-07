import Dependencies
import Foundation

/// Remembers the ETag of each text file the editor read or saved, so a save can tell that someone
/// else changed the file in between. Keys carry the account scope the effect started under, so a
/// late answer after an account switch lands in its own account, and `clear(scope:)` and `clearAll()`
/// drop it at every session boundary (rule #11). Lock guarded so the `Sendable` service can share it.
public final class TextEditorETagStore: @unchecked Sendable {
    private enum Constants {
        static let separator = "\n"
        static let pathSeparator = "/"
    }

    private let lock = NSLock()
    private var etags: [String: String] = [:]

    public init() {}

    static func key(scope: String, serverURL: URL, path: String) -> String {
        [scope, serverURL.absoluteString, path].joined(separator: Constants.separator)
    }

    func etag(for key: String) -> String? {
        lock.withLock { etags[key] }
    }

    func set(_ etag: String?, for key: String) {
        lock.withLock { etags[key] = etag }
    }

    public func clearAll() {
        lock.withLock { etags.removeAll() }
    }

    public func clear(scope: String) {
        let prefix = scope + Constants.separator
        lock.withLock { etags = etags.filter { !$0.key.hasPrefix(prefix) } }
    }

    /// Drops a path and, for a folder, everything beneath it: after a rename, move or delete the old
    /// path no longer names the file the stored tag belonged to.
    func forget(scope: String, serverURL: URL, path: String) {
        let exact = Self.key(scope: scope, serverURL: serverURL, path: path)
        let beneath = exact + Constants.pathSeparator
        lock.withLock { etags = etags.filter { $0.key != exact && !$0.key.hasPrefix(beneath) } }
    }
}

extension TextEditorETagStore: DependencyKey {
    public static let liveValue = TextEditorETagStore()
    public static var testValue: TextEditorETagStore {
        TextEditorETagStore()
    }
}

public extension DependencyValues {
    var textEditorETagStore: TextEditorETagStore {
        get { self[TextEditorETagStore.self] }
        set { self[TextEditorETagStore.self] = newValue }
    }
}
