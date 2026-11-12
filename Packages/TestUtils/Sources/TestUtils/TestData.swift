import Foundation

/// Plain values that many tests share, defined once so a name or credential is never retyped.
/// Only strings and URLs live here: TestUtils must not depend on the app's models.

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
}

public enum TestAccount {
    public static let username = "phillip"
    public static let password = "hunter2"
    /// A six digit authenticator code.
    public static let totpCode = "123456"
}

public enum TestHost {
    public static let server = "files.example.com"
    public static let example = "example.com"

    public static var serverURL: URL { httpsURL(server) }

    private static func httpsURL(_ host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components.url ?? URL(fileURLWithPath: "/")
    }
}
