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
    public var filesDone = 0
    public var bytesTotal: Int64 = 0
    public var bytesDone: Int64 = 0
    /// The file currently downloading, for the "Downloading <name>" line.
    public var currentName = ""

    public init() {}

    /// True while a run is preparing or downloading, so the Settings screen shows the progress row
    /// rather than the idle "available offline" summary.
    public var isActive: Bool {
        phase == .preparing || phase == .downloading
    }

    /// 0...1 over bytes once totals are known, so the bar tracks real transferred size rather than
    /// file count (one large video shouldn't jump the bar the same as one tiny text file). Falls back
    /// to file count when the listing reported no sizes, so the bar still advances instead of sitting
    /// at 0 until it snaps to 100.
    public var fractionComplete: Double {
        if bytesTotal > 0 {
            return min(max(Double(bytesDone) / Double(bytesTotal), 0), 1)
        }
        guard filesTotal > 0 else { return phase == .completed ? 1 : 0 }
        return min(max(Double(filesDone) / Double(filesTotal), 0), 1)
    }
}
