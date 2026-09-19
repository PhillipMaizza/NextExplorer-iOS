@testable import FilesFeature
import Testing

struct OfflineDownloadProgressTests {
    @Test
    func currentFileNumberShowsTheFileInFlightWhileDownloading() {
        var progress = OfflineDownloadProgress()
        progress.phase = .downloading
        progress.filesTotal = 3
        progress.filesDone = 0
        // Downloading the first file reads "1 of 3", not "0 of 3".
        #expect(progress.currentFileNumber == 1)

        progress.filesDone = 1
        #expect(progress.currentFileNumber == 2)
    }

    @Test
    func currentFileNumberIsCappedAndFullOnCompletion() {
        var progress = OfflineDownloadProgress()
        progress.phase = .downloading
        progress.filesTotal = 3
        progress.filesDone = 3
        // Never overshoots the total while the last file finishes.
        #expect(progress.currentFileNumber == 3)

        progress.phase = .completed
        #expect(progress.currentFileNumber == 3)
        #expect(progress.fractionComplete == 1)
    }

    @Test
    func fractionTracksProcessedUnitsAgainstTheTotal() {
        var progress = OfflineDownloadProgress()
        progress.phase = .downloading
        progress.filesTotal = 4
        progress.unitsDone = 1
        #expect(progress.fractionComplete == 0.25)
    }
}
