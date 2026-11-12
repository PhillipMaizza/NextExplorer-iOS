import Foundation

// Plain values that many tests share, defined once so a name or credential is never retyped.
// Only strings and URLs live here: TestUtils must not depend on the app's models.

public enum TestFolder {
    public static let docs = "Docs"
    public static let documents = "Documents"
    public static let photos = "Photos"
    public static let inbox = "Inbox"
    public static let archive = "Archive"
    public static let media = "Media"
    public static let files = "Files"
    public static let other = "other"
}

public enum TestFile {
    public static let aText = "a.txt"
    public static let bText = "b.txt"
    public static let notes = "notes.txt"
    public static let aPhoto = "a.jpg"
    public static let bPhoto = "b.jpg"
    public static let vacationPhoto = "vacation.jpg"
    public static let photo = "photo.jpg"
    public static let report = "report.pdf"
    public static let aPDF = "a.pdf"
    /// A third photo name next to a.jpg and b.jpg.
    public static let cPhoto = "c.jpg"
}

public enum TestAccount {
    public static let username = "phillip"
    public static let password = "hunter2"
    /// A six digit authenticator code.
    public static let totpCode = "123456"
    /// A password the server rejects.
    public static let wrongPassword = "wrong"
    /// A second password or passphrase that is rejected.
    public static let rejectedPassword = "nope"
    /// A backup code in the dashed eleven character form.
    public static let recoveryCode = "2HSMP-G9ZSJ"
    /// A six digit code the server rejects.
    public static let invalidTotpCode = "000000"
    /// A base32 authenticator secret.
    public static let totpSecret = "JBSWY3DPEHPK3PXP"
}

public enum TestHost {
    public static let server = "files.example.com"
    public static let example = "example.com"
    /// A generic https server address.
    public static let exampleURLString = "https://example.com"
    /// The default test server address as text.
    public static let serverURLString = "https://files.example.com"
    /// The default test server with an explicit port.
    public static let serverWithPort = "files.example.com:8443"
    /// First of two distinct servers.
    public static let firstServer = "a.example.com"
    /// First of two distinct servers as an address.
    public static let firstServerURLString = "https://a.example.com"
    /// Second of two distinct servers.
    public static let secondServer = "b.example.com"
    /// Second of two distinct servers as an address.
    public static let secondServerURLString = "https://b.example.com"
    /// A server host named like the product.
    public static let nextExplorer = "nextexplorer.example.com"
    /// A server address named like the product.
    public static let nextExplorerURLString = "https://nextexplorer.example.com"
    /// A short host used where only the shape of the address matters.
    public static let shortHost = "a.com"

    public static var serverURL: URL {
        httpsURL(server)
    }

    private static func httpsURL(_ host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

public enum TestSession {
    /// The session cookie name the local auth path uses.
    public static let cookieName = "connect.sid"
    /// A session cookie value.
    public static let cookieValue = "abc"
    /// The cookie value a successful login returns.
    public static let loginCookieValue = "abc123"
    /// The cookie value background uploads authenticate with.
    public static let uploadCookieValue = "secret"
    /// A cookie value that replaced the stored one after a re-login.
    public static let refreshedCookieValue = "fresh"
}

public enum TestStorageKey {
    /// A Keychain item key for one stored session.
    public static let session = "session"
    /// The Keychain key all stored sessions live under.
    public static let storedSessions = "storedSessions"
    /// The pre multi account Keychain key for the single active session.
    public static let legacySession = "currentSession"
}

public enum TestUser {
    /// First persona of an account pair.
    public static let alice = "alice"
    /// Second persona of an account pair.
    public static let bob = "bob"
    /// A third account name.
    public static let jane = "jane"
    /// The account name the second factor tests sign in with.
    public static let asmith = "asmith"
    /// An account name that differs from the signed in one.
    public static let someoneElse = "someone else"
}

public enum TestFailure {
    /// The message a simulated transport failure carries.
    public static let offline = "offline"
}

public enum TestValue {
    /// A stale value a test replaces.
    public static let outdated = "old"
    /// A string of spaces that counts as empty after trimming.
    public static let blank = "   "
}

public enum TestCertificate {
    /// The subject of the test client certificate.
    public static let subject = "Dev Client"
}

public enum TestAPIToken {
    /// The identifier of the sample API token.
    public static let id = "t1"
    /// The plain text of a freshly issued API token.
    public static let secret = "nxt_abc.def"
}

public enum TestUpload {
    /// The identifier of a staged upload batch.
    public static let batchID = "BATCH"
}

public enum TestPath {
    /// The Docs folder as a lowercase cache path.
    public static let docsLowercase = "docs"
    /// A note inside Docs.
    public static let docsNote = "Docs/n.txt"
    /// A notes file inside Docs.
    public static let docsNotes = "Docs/notes.txt"
    /// A file inside Docs that does not exist yet.
    public static let docsNew = "Docs/new.txt"
    /// A nested photo folder.
    public static let photos2026 = "Photos/2026"
    /// A folder three levels deep.
    public static let mediaPhotos2024 = "Media/Photos/2024"
    /// A folder two levels deep.
    public static let mediaPhotos = "Media/Photos"
    /// A sibling folder under Documents.
    public static let documentsWork = "Documents/Work"
    /// A Docs folder under a Home root.
    public static let homeDocs = "Home/Docs"
    public static let documentsReports = "Documents/Reports"
}

public enum TestCacheKey {
    /// The cache key the favorites list is stored under.
    public static let favorites = "favorites"
}

public enum TestETag {
    /// An entity tag value.
    public static let first = "v1"
    /// A second entity tag value.
    public static let second = "v2"
}

/// File kinds the listing carries (`FileItem.kind`). A folder is `FileItem.directoryKind` from CoreModels.
public enum TestKind {
    public static let text = "txt"
    public static let pdf = "pdf"
    public static let photo = "jpg"
    public static let video = "mp4"
}
