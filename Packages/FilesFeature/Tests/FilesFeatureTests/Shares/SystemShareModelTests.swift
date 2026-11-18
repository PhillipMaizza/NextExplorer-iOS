import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Getting a file ready for the share sheet: a local file at once, a server file once downloaded, a
/// failure marked, a 401 signing out, and a cancelled download never read as a failure.
@Suite(.isolatedDependencies)
@MainActor
struct SystemShareModelTests {
    private enum Constants {
        static let downloaded = URL(fileURLWithPath: "/cache/report.pdf")
        static let local = URL(fileURLWithPath: "/device/report.pdf")
    }

    private let report = BrowseFixtures.file(TestFile.report, in: TestFolder.docs)

    private func model(download: @escaping @Sendable (URL, FileItem) async throws -> URL) -> SystemShareModel {
        withDependencies {
            $0.filesClient.downloadRawFile = download
        } operation: {
            SystemShareModel()
        }
    }

    @Test("A local file is handed over at once, a missing one is not")
    func localFile() {
        let model = model { _, _ in Constants.downloaded }
        model.prepare(.local(nil))
        #expect(model.shareURL == nil)
        model.prepare(.local(Constants.local))
        #expect(model.shareURL?.url == Constants.local)
        #expect(!model.isPreparing)
    }

    @Test("A server file is shared once downloaded")
    func remoteFile() async {
        let model = model { _, _ in Constants.downloaded }
        model.prepare(.remote(report, serverURL: BrowseTestSupport.serverURL))
        #expect(model.isPreparing)
        await model.download?.value
        #expect(model.shareURL?.url == Constants.downloaded)
        #expect(!model.isPreparing)
        #expect(!model.didFail)
    }

    @Test("A failed download is marked, and clearing it resets the mark")
    func failedDownload() async {
        let model = model { _, _ in throw FilesClientError.offline }
        model.prepare(.remote(report, serverURL: BrowseTestSupport.serverURL))
        await model.download?.value
        #expect(model.didFail)
        #expect(model.shareURL == nil)
        model.clearFailure()
        #expect(!model.didFail)
    }

    @Test("A 401 while downloading signs the user out")
    func sessionExpired() async {
        @Shared(.inMemory(SessionExpiry.sharedKey)) var sessionDidExpire = false
        $sessionDidExpire.withLock { $0 = false }
        let model = model { _, _ in throw FilesClientError.sessionExpired }
        model.prepare(.remote(report, serverURL: BrowseTestSupport.serverURL))
        await model.download?.value
        #expect(sessionDidExpire)
        #expect(model.didFail)
    }

    @Test("A download that still lands after leaving shares nothing and is not a failure")
    func cancelledDownload() async {
        let gate = AsyncGate()
        let model = model { _, _ in
            // Held on a task of its own, so the cancel does not reach it and the download still
            // succeeds: only the model's own check keeps the late file from the share sheet.
            await Task { try? await gate.wait() }.value
            return Constants.downloaded
        }
        model.prepare(.remote(report, serverURL: BrowseTestSupport.serverURL))
        let download = model.download
        model.cancel()
        gate.open()
        await download?.value
        #expect(!model.didFail)
        #expect(model.shareURL == nil)
        #expect(!model.isPreparing)
    }

    @Test("A share started right after a cancel runs at once and hands over its own file")
    func aShareAfterACancelStartsAtOnce() async {
        let gate = AsyncGate()
        let calls = LockIsolated(0)
        let model = model { _, _ in
            let call = calls.withValue { $0 += 1; return $0 }
            if call == 1 {
                await Task { try? await gate.wait() }.value
            }
            return Constants.downloaded
        }
        model.prepare(.remote(report, serverURL: BrowseTestSupport.serverURL))
        let first = model.download
        model.cancel()
        #expect(!model.isPreparing)

        model.prepare(.remote(report, serverURL: BrowseTestSupport.serverURL))
        await model.download?.value
        #expect(calls.value == 2)
        #expect(model.shareURL?.url == Constants.downloaded)
        gate.open()
        await first?.value
        #expect(!model.isPreparing)
    }

    @Test("A second tap while one download runs starts no other")
    func secondTapIsIgnored() async {
        let calls = LockIsolated(0)
        let model = model { _, _ in
            calls.withValue { $0 += 1 }
            return Constants.downloaded
        }
        model.prepare(.remote(report, serverURL: BrowseTestSupport.serverURL))
        model.prepare(.remote(report, serverURL: BrowseTestSupport.serverURL))
        await model.download?.value
        #expect(calls.value == 1)
    }
}
