import Foundation

/// Where a downloaded file/folder gets saved — the user's own choice, surfaced as a
/// Settings row. `.documents` is visible/manageable from the iOS Files app;
/// `.cache` stays app-private and is purgeable by the system under storage pressure.
public enum DownloadLocation: String, CaseIterable, Identifiable, Equatable, Sendable {
    case documents, cache

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .documents: "Documents"
        case .cache: "Cache"
        }
    }
}
