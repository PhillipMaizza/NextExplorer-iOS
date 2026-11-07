import Foundation

/// Reads a file the way the system expects for files other processes manage: a coordinated read,
/// after asking iCloud to download a file that is only a placeholder, so a bare read never sees
/// an empty or missing body.
struct FileAccess: Sendable {
    var ubiquityStatus: @Sendable (URL) -> URLUbiquitousItemDownloadingStatus?
    var startDownload: @Sendable (URL) throws -> Void

    static let live = FileAccess(
        ubiquityStatus: { url in
            try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        },
        startDownload: { try FileManager.default.startDownloadingUbiquitousItem(at: $0) }
    )

    /// `nil` means the file is not an iCloud item at all.
    static func needsDownload(_ status: URLUbiquitousItemDownloadingStatus?) -> Bool {
        status == .notDownloaded
    }

    /// Runs `body` with the file readable. The coordinator waits for a downloading item to land.
    func read<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        if Self.needsDownload(ubiquityStatus(url)) {
            try startDownload(url)
        }
        var coordinationError: NSError?
        var outcome: Result<T, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            outcome = Result { try body(readURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let outcome else { throw CocoaError(.fileReadUnknown) }
        return try outcome.get()
    }
}
