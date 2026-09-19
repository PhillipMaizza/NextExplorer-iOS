import Foundation

/// Live state of the offline download run, published by `OfflineDownloadsFeature` and read by the
/// Settings screen through `@Shared(.inMemory(sharedKey))`. Because the engine is a session lifetime
/// sibling of Settings (not torn down on a tab switch), the run keeps advancing while the user is
/// elsewhere, and the Settings screen reflects wherever it got to when they return.
public struct OfflineDownloadProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Walking the pinned folders to count the files and total bytes before downloading.
        case preparing
        case downloading
        case completed
        case failed(String)
    }

    public static let sharedKey = "offlineDownloadProgress"

    public var phase: Phase = .idle
    public var filesTotal = 0
    /// Files fully stored so far, for the "X of Y files" line. Counts successes only.
    public var filesDone = 0
    /// Files processed so far as a smooth count, including the fraction of the files currently
    /// streaming (a half downloaded file contributes 0.5). Drives the bar so it tracks the visible
    /// file count rather than raw bytes: a run that is "338 of 341 files" reads as nearly full even
    /// when the three remaining files are huge, and still advances mid file instead of freezing on a
    /// large one. A failed file counts as processed (it does not stall the bar) but not as done.
    public var unitsDone: Double = 0
    /// The file currently downloading, for the "Downloading <name>" line.
    public var currentName = ""

    public init() {}

    /// True while a run is preparing or downloading, so the Settings screen shows the progress row
    /// rather than the idle "available offline" summary.
    public var isActive: Bool {
        phase == .preparing || phase == .downloading
    }

    /// The file number to show in "X of Y files". While downloading it is the file currently in
    /// flight (1 based) rather than the count already finished, so a run reads "1 of 3" while the
    /// first file downloads instead of a confusing "0 of 3". Completed reads "Y of Y".
    public var currentFileNumber: Int {
        switch phase {
        case .completed:
            filesTotal
        case .downloading:
            filesTotal == 0 ? 0 : min(filesDone + 1, filesTotal)
        default:
            filesDone
        }
    }

    /// 0...1 over the processed file count (with sub file smoothing), so the bar and the
    /// "X of Y files" label always agree. A completed run reads full even if a file or two failed
    /// (those stay pending for the next sync).
    public var fractionComplete: Double {
        if phase == .completed {
            return 1
        }
        guard filesTotal > 0 else { return 0 }
        return min(max(unitsDone / Double(filesTotal), 0), 1)
    }
}
