import Foundation

/// How the next upload goes out. Mirrors the web client's decision: forced chunking wins, then a
/// chunk size this server origin has already taught us, otherwise one direct request.
public enum UploadMode: Equatable, Sendable {
    case direct
    case chunked(chunkSizeBytes: Int)

    /// Below this a direct upload finishes before a reverse proxy has a chance to refuse it.
    public static let largeFileBytes = 8 * UploadSettings.bytesPerMiB

    /// Chunk sizes tried, largest first, when a direct upload is refused for its size.
    public static let fallbackLadderMiB = [96, 64, 32, 16, 8]

    /// Decides from the server's `uploads` settings and the chunk size remembered for this origin.
    public static func resolve(settings: UploadSettings?, rememberedMiB: Int?) -> UploadMode {
        guard let settings else { return .direct }
        if settings.isChunkedEnabled {
            return .chunked(chunkSizeBytes: settings.chunkSizeBytes)
        }
        if settings.isChunkedAutoFallback, let rememberedMiB {
            return .chunked(chunkSizeBytes: rememberedMiB * UploadSettings.bytesPerMiB)
        }
        return .direct
    }

    /// The next rung after a refusal: below the size that was refused when none is remembered yet,
    /// otherwise one step down from the remembered one. `nil` once the smallest rung has failed.
    public static func nextFallbackMiB(current: Int?, refusedBytes: Int) -> Int? {
        let ladder = fallbackLadderMiB
        guard let current else {
            let refusedMiB = refusedBytes / UploadSettings.bytesPerMiB
            return ladder.first { $0 < refusedMiB } ?? ladder[0]
        }
        guard let index = ladder.firstIndex(of: current), index + 1 < ladder.count else { return nil }
        return ladder[index + 1]
    }
}
