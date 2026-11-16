import Foundation
@testable import NetworkClient
import Testing
import TestUtils

@Suite("DownloadTaskHolder")
struct DownloadTaskHolderTests {
    private func makeTask() -> (URLSession, URLSessionDownloadTask) {
        let session = URLSession(configuration: .ephemeral)
        return (session, session.downloadTask(with: TestHost.serverURL))
    }

    @Test("cancelling after the task was stored cancels it")
    func cancelStoredTask() {
        let (session, task) = makeTask()
        defer { session.invalidateAndCancel() }
        let holder = DownloadTaskHolder()

        #expect(holder.store(task))
        holder.cancel()

        // A task that never started can finish cancelling at once, so either state proves it; an
        // uncancelled one stays suspended.
        #expect([.canceling, .completed].contains(task.state))
    }

    @Test("a task stored after cancellation is refused so the caller cancels it instead of resuming")
    func storeAfterCancelIsRefused() {
        let (session, task) = makeTask()
        defer { session.invalidateAndCancel() }
        let holder = DownloadTaskHolder()

        holder.cancel()

        #expect(!holder.store(task))
        #expect(task.state == .suspended)
    }
}
