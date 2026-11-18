@testable import FilesFeature
import Testing

/// Thumbnail writers never run the preview cache's own eviction, so the schedule asks for a trim
/// every so many writes.
struct CacheTrimScheduleTests {
    @Test("A trim falls due on every third write and the count starts over after each")
    func trimIsDueEveryInterval() {
        let schedule = CacheTrimSchedule(every: 3)

        let due = (1 ... 7).map { _ in schedule.recordWrite() }

        #expect(due == [false, false, true, false, false, true, false])
    }
}
