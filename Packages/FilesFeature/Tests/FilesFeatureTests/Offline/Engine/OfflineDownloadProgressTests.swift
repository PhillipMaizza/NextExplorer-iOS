@testable import FilesFeature
import Foundation
import Testing
import TestUtils

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

    @Test
    func secondsRemainingScalesElapsedTimeByWhatIsLeft() {
        let start = MockDate.date
        var progress = OfflineDownloadProgress()
        progress.phase = .downloading
        progress.filesTotal = 4
        progress.unitsDone = 1
        progress.downloadStartedAt = start
        #expect(progress.secondsRemaining(now: start.addingTimeInterval(30)) == 90)
    }

    @Test
    func secondsRemainingIsUnknownBeforeAnyProgressAndOutsideDownloading() {
        let start = MockDate.date
        var progress = OfflineDownloadProgress()
        progress.phase = .downloading
        progress.filesTotal = 4
        progress.downloadStartedAt = start
        #expect(progress.secondsRemaining(now: start.addingTimeInterval(30)) == nil)

        progress.unitsDone = 2
        progress.phase = .preparing
        #expect(progress.secondsRemaining(now: start.addingTimeInterval(30)) == nil)
    }
}
