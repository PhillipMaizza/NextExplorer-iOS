import Foundation

/// Collapses concurrent downloads that would land in the same cache file into one shared
/// transfer. Keyed by the destination file path, so a PDF's opportunistic thumbnail fetch
/// (`previewFileLowPriority`) and a tap-to-open of that same PDF (`previewFile`) run the
/// bytes down once and both get the result — instead of two transfers racing on the
/// `moveItem` into the shared slot, where the loser throws a spurious error.
actor PreviewDownloadCoordinator {
    private var inFlight: [String: Task<URL, Error>] = [:]

    /// Runs `work` to produce the file at `fileURL`, unless a call for the same path is
    /// already in progress — in which case this awaits and returns that one's result.
    func run(
        forFileAt fileURL: URL,
        _ work: @Sendable @escaping () async throws -> URL
    ) async throws -> URL {
        let key = fileURL.path

        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task { try await work() }
        inFlight[key] = task
        let result = await task.result
        // Only the call that owns the task clears it; a shared waiter's clear is a harmless
        // no-op (already gone, or replaced by a newer download for the same path).
        if inFlight[key] == task {
            inFlight[key] = nil
        }
        return try result.get()
    }
}
