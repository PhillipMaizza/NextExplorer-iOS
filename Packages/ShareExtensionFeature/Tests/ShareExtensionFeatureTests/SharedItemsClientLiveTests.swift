import ComposableArchitecture
import CoreModels
import Foundation
import Localization
@testable import ShareExtensionFeature
import ShareUploads
import Testing
import TestUtils
import UniformTypeIdentifiers

/// The live client against real `NSItemProvider`s, staged into a temporary batch that is never
/// started, so nothing reaches a background session.
struct SharedItemsClientLiveTests {
    private let credentials = SessionCredentials.preview

    private func temporaryFile(named name: String, contents: String = "contents") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func readableProvider(named name: String) throws -> NSItemProvider {
        let file = try temporaryFile(named: name)
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerFileRepresentation(for: .pdf, visibility: .all, openInPlace: false) { completion in
            completion(file, false, nil)
            return nil
        }
        return provider
    }

    private func failingProvider(
        named name: String?,
        error: any Error = CocoaError(.fileReadNoSuchFile)
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerFileRepresentation(for: .pdf, visibility: .all, openInPlace: false) { completion in
            completion(nil, false, error)
            return nil
        }
        return provider
    }

    private func client(_ providers: [NSItemProvider]) -> SharedItemsClient {
        .live(providers: providers, requestNotificationPermission: {})
    }

    @Test("one unreadable item is skipped and named, and the others stay staged")
    func anUnreadableItemDoesNotCostTheBatch() async throws {
        let providers = try [
            readableProvider(named: "first.pdf"),
            failingProvider(named: Constants.brokenName),
            readableProvider(named: "third.pdf"),
        ]
        let client = client(providers)

        let report = try await client.prepare(credentials, TestFolder.photos, nil) { _ in }

        #expect(report.stagedCount == 2)
        #expect(report.failures == [ItemFailure(index: 1, name: Constants.brokenName, cause: .cannotRead)])
        client.discard()
    }

    @Test("a failing item without a name is still identified by its position")
    func anUnnamedFailureGetsAPositionName() async throws {
        let client = try client([readableProvider(named: TestFile.aPDF), failingProvider(named: nil)])

        let report = try await client.prepare(credentials, TestFolder.photos, nil) { _ in }

        let failure = try #require(report.failures.first)
        #expect(failure.index == 1)
        #expect(!failure.name.isEmpty)
        client.discard()
    }

    @Test("an out of space failure is reported with that cause")
    func aFullDeviceIsNamedAsTheCause() async throws {
        let client = client([failingProvider(named: "big.mov", error: CocoaError(.fileWriteOutOfSpace))])

        let report = try await client.prepare(credentials, TestFolder.photos, nil) { _ in }

        #expect(report.stagedCount == 0)
        #expect(report.failures.map(\.cause) == [.notEnoughSpace])
        client.discard()
    }

    @Test("a retry pass stages only the requested items into the same batch")
    func aRetryAddsToTheSameBatch() async throws {
        let failsOnce = LockIsolated(true)
        let flaky = NSItemProvider()
        flaky.suggestedName = Constants.flakyName
        let file = try temporaryFile(named: Constants.flakyName)
        flaky.registerFileRepresentation(for: .pdf, visibility: .all, openInPlace: false) { completion in
            if failsOnce.withValue({ value -> Bool in
                defer { value = false }
                return value
            }) {
                completion(nil, false, CocoaError(.fileReadUnknown))
            } else {
                completion(file, false, nil)
            }
            return nil
        }
        let client = try client([readableProvider(named: "ok.pdf"), flaky])

        let first = try await client.prepare(credentials, TestFolder.photos, nil) { _ in }
        #expect(first.stagedCount == 1)
        #expect(first.failures.map(\.index) == [1])

        let second = try await client.prepare(credentials, TestFolder.photos, [1]) { _ in }
        #expect(second.stagedCount == 2, "the earlier file is still staged")
        #expect(second.failures.isEmpty)
        client.discard()
    }

    @Test("an item with no file, such as a link, is skipped quietly")
    func aLinkIsNotAFailure() async throws {
        let link = try NSItemProvider(object: #require(URL(string: TestHost.exampleURLString)) as NSURL)
        let client = client([link])

        let report = try await client.prepare(credentials, TestFolder.photos, nil) { _ in }

        #expect(report.stagedCount == 0)
        #expect(report.failures.isEmpty)
        client.discard()
    }

    @Test("progress reports the finished items and ends complete")
    func progressEndsComplete() async throws {
        let seen = LockIsolated<[PreparationProgress]>([])
        let client = try client([readableProvider(named: TestFile.aPDF), readableProvider(named: "b.pdf")])

        _ = try await client.prepare(credentials, TestFolder.photos, nil) { progress in
            seen.withValue { $0.append(progress) }
        }

        #expect(seen.value.last == PreparationProgress(completed: 2))
        #expect(seen.value.map(\.completed).contains(1))
        client.discard()
    }

    /// Changes the provider's `Progress` over and over on another thread until stopped: the
    /// provider hooks the progress it was handed into its own only once the read has started, so
    /// a change has to come after that for anyone to see it.
    private final class ProgressPump: @unchecked Sendable {
        fileprivate enum Constants {
            static let nearlyDone: Int64 = 90
            static let done: Int64 = 100
            /// The provider counts its own work too, so the fraction it reports for a nearly
            /// finished read is well past this.
            static let reportedAtLeast = 0.5
        }

        private let lock = NSLock()
        private var isStopped = false
        private let progress: Progress

        init(_ progress: Progress) {
            self.progress = progress
        }

        func start() {
            DispatchQueue.global().async { [self] in
                var completed = Constants.nearlyDone
                while !lock.withLock({ isStopped }) {
                    progress.completedUnitCount = completed
                    completed = completed == Constants.nearlyDone ? Constants.done : Constants.nearlyDone
                }
            }
        }

        func stop() {
            lock.withLock { isStopped = true }
        }
    }

    @Test("the Progress the provider returns drives the reported fraction", .timeLimit(.minutes(1)))
    func theProvidersProgressIsReported() async throws {
        let file = try temporaryFile(named: "video.pdf")
        let progress = Progress(totalUnitCount: 100)
        let pump = ProgressPump(progress)
        defer { pump.stop() }
        let release = LockIsolated<(@Sendable () -> Void)?>(nil)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(for: .pdf, visibility: .all, openInPlace: false) { completion in
            nonisolated(unsafe) let finish = completion
            release.setValue { finish(file, false, nil) }
            pump.start()
            return progress
        }
        let (fractions, report) = AsyncStream<Double>.makeStream()
        let client = client([provider])

        let task = Task {
            try await client.prepare(credentials, TestFolder.photos, nil) { reported in
                report.yield(reported.fraction)
            }
        }
        var reached: Double?
        for await fraction in fractions where fraction >= ProgressPump.Constants.reportedAtLeast {
            reached = fraction
            break
        }
        pump.stop()
        release.value?()
        let preparation = try await task.value

        #expect(
            reached.map { $0 >= ProgressPump.Constants.reportedAtLeast && $0 <= 1 } == true,
            "the fraction of the file being read reaches the caller"
        )
        #expect(preparation.stagedCount == 1)
        client.discard()
    }

    @Test("cancelling cancels the provider's Progress, drops the batch, and throws", .timeLimit(.minutes(1)))
    func cancellingStopsTheLoadAndDiscardsTheBatch() async throws {
        let progress = Progress(totalUnitCount: 100)
        let (started, signalStarted) = AsyncStream.makeStream(of: Void.self)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(for: .pdf, visibility: .all, openInPlace: false) { _ in
            signalStarted.yield()
            return progress
        }
        let client = client([provider])

        let task = Task {
            try await client.prepare(credentials, TestFolder.photos, nil) { _ in }
        }
        var iterator = started.makeAsyncIterator()
        await iterator.next()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(progress.isCancelled, "the copy itself is stopped, not just ignored")
        #expect(throws: (any Error).self) { try client.start() }
    }

    @Test("a folder shared next to a file is named as a folder and the file still stages")
    func aFolderIsReportedNotSkipped() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name(), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let folderProvider = NSItemProvider()
        folderProvider.suggestedName = Constants.holidayFolder
        folderProvider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(folder as NSURL, nil)
        }
        let client = try client([readableProvider(named: TestFile.aPDF), folderProvider])

        let report = try await client.prepare(credentials, TestFolder.photos, nil) { _ in }

        #expect(report.stagedCount == 1)
        #expect(report.failures == [ItemFailure(index: 1, name: Constants.holidayFolder, cause: .folder)])
        client.discard()
    }

    @Test("a file URL with nothing behind it is a read failure, not a silent skip")
    func aMissingFileIsReported() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(TestID.name()).txt")
        let provider = NSItemProvider()
        provider.suggestedName = Constants.goneName
        provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(missing as NSURL, nil)
        }
        let client = client([provider])

        let report = try await client.prepare(credentials, TestFolder.photos, nil) { _ in }

        #expect(report.stagedCount == 0)
        #expect(report.failures == [ItemFailure(index: 0, name: Constants.goneName, cause: .cannotRead)])
        client.discard()
    }

    @Test("a provider carrying a Live Photo is counted as one")
    func livePhotosAreCounted() throws {
        let live = NSItemProvider()
        live.registerDataRepresentation(for: .livePhoto, visibility: .all) { completion in
            completion(Data("live".utf8), nil)
            return nil
        }
        let client = try client([live, readableProvider(named: "plain.pdf")])

        #expect(client.livePhotoCount() == 1)
        #expect(client.count() == 2)
        #expect(ProviderStager.isLivePhoto(live))
    }

    @Test("starting without a staged batch throws instead of uploading nothing")
    func startNeedsABatch() {
        let client = client([])
        #expect(throws: (any Error).self) { try client.start() }
    }

    @Test("discarding drops the staged batch once, and a second discard changes nothing")
    func discardDropsTheBatchOnce() async throws {
        let client = try client([readableProvider(named: TestFile.aPDF)])
        let report = try await client.prepare(credentials, TestFolder.photos, nil) { _ in }
        #expect(report.stagedCount == 1)

        client.discard()
        client.discard()

        #expect(throws: (any Error).self) { try client.start() }
        #expect(client.count() == 1, "the shared items themselves are untouched")
    }

    @Test("a batch is handed to exactly one taker, so a start and a discard never both act on it")
    func aBatchIsTakenOnce() throws {
        let pending = PendingBatch()
        let batch = try BackgroundUploader.shared.makeBatch(credentials: credentials, destination: TestFolder.photos)
        pending.batch = batch

        #expect(pending.take()?.id == batch.id)
        #expect(pending.take() == nil, "once start has taken it a discard finds nothing to delete")
        #expect(pending.batch == nil)
        BackgroundUploader.shared.discard(batch)
    }
}

struct ProviderStagerTests {
    @Test(arguments: [
        (CocoaError(.fileWriteOutOfSpace), ItemFailureCause.notEnoughSpace),
        (CocoaError(.fileReadNoSuchFile), .cannotRead),
        (CocoaError(.fileReadNoPermission), .cannotRead),
        (CocoaError(.fileReadCorruptFile), .cannotRead),
        (CocoaError(.userCancelled), .other),
    ])
    func causesFromCocoaErrors(error: CocoaError, expected: ItemFailureCause) {
        #expect(ProviderStager.cause(of: error) == expected)
    }

    @Test("a full disk reported as a POSIX error, directly or underneath another error, is not enough space")
    func posixSpaceFailures() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let quota = NSError(domain: NSPOSIXErrorDomain, code: Int(EDQUOT))
        let wrapped = NSError(domain: "test.wrapper", code: -1, userInfo: [NSUnderlyingErrorKey: posix])
        #expect(ProviderStager.cause(of: posix) == .notEnoughSpace)
        #expect(ProviderStager.cause(of: quota) == .notEnoughSpace)
        #expect(ProviderStager.cause(of: wrapped) == .notEnoughSpace)
        #expect(ProviderStager.cause(of: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))) == .other)
    }

    @Test("a space failure from the uploader maps to not enough space")
    func uploaderSpaceFailure() {
        #expect(ProviderStager.cause(of: ShareUploadError.insufficientSpace) == .notEnoughSpace)
    }

    @Test("a shared folder maps to the folder cause")
    func folderCause() {
        #expect(ProviderStager.cause(of: ShareUploadError.isFolder) == .folder)
    }

    @Test("an unknown error is reported as other, never with its raw description")
    func unknownErrorIsOther() {
        struct Odd: Error {}
        #expect(ProviderStager.cause(of: Odd()) == .other)
    }

    @Test("a failure line names the file and the cause")
    func failureLineNamesTheFile() {
        let failure = ItemFailure(index: 3, name: ShareExtensionFeatureTestValue.movieName, cause: .notEnoughSpace)
        #expect(failure.line.contains(ShareExtensionFeatureTestValue.movieName))
        #expect(failure.line.contains(ItemFailureCause.notEnoughSpace.message))
    }
}

private enum Constants {
    static let brokenName = "broken.pdf"
    static let flakyName = "flaky.pdf"
    static let goneName = "gone.txt"
    static let holidayFolder = "Holiday"
}
