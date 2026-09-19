@testable import FilesFeature
import Testing

struct DownloadProgressCounterTests {
    @Test
    func inFlightFractionsAccumulateAsPartialUnits() {
        let counter = DownloadProgressCounter()
        // Two files in flight: one 50%, one 25% -> 0.75 of a file processed, none done yet.
        _ = counter.progress(key: 0, fileFraction: 0.5)
        let snapshot = counter.progress(key: 1, fileFraction: 0.25)
        #expect(snapshot?.unitsDone == 0.75)
        #expect(snapshot?.filesDone == 0)
    }

    @Test
    func completionFoldsAWholeUnitAndDropsThePartial() {
        let counter = DownloadProgressCounter()
        _ = counter.progress(key: 0, fileFraction: 0.4)
        let done = counter.complete(key: 0, success: true)
        #expect(done.unitsDone == 1)
        #expect(done.filesDone == 1)
    }

    @Test
    func aFailedFileAdvancesTheBarButIsNotCountedAsDone() {
        let counter = DownloadProgressCounter()
        let failed = counter.complete(key: 0, success: false)
        #expect(failed.unitsDone == 1)
        #expect(failed.filesDone == 0)
        let ok = counter.complete(key: 1, success: true)
        #expect(ok.unitsDone == 2)
        #expect(ok.filesDone == 1)
    }

    @Test
    func fractionIsCappedAtOnePerFile() {
        let counter = DownloadProgressCounter()
        let snapshot = counter.progress(key: 0, fileFraction: 5)
        #expect(snapshot?.unitsDone == 1)
    }

    @Test
    func aLateProgressForACompletedKeyIsIgnored() {
        let counter = DownloadProgressCounter()
        _ = counter.complete(key: 0, success: true)
        // A callback arriving after completion must not re-add the slot and double count.
        #expect(counter.progress(key: 0, fileFraction: 0.3) == nil)
        let done = counter.complete(key: 1, success: true)
        #expect(done.unitsDone == 2)
    }
}
