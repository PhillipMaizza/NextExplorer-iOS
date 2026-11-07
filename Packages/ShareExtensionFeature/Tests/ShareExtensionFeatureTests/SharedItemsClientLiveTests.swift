import ComposableArchitecture
import CoreModels
import Foundation
@testable import ShareExtensionFeature
import ShareUploads
import Testing
import UniformTypeIdentifiers

/// The live client against real `NSItemProvider`s, staged into a temporary batch that is never
/// started, so nothing reaches a background session.
struct SharedItemsClientLiveTests {
    private let credentials = SessionCredentials.preview

    private func temporaryFile(named name: String, contents: String = "contents") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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

    private func failingProvider(named name: String?, error: any Error = CocoaError(.fileReadNoSuchFile)) -> NSItemProvider {
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
            failingProvider(named: "broken.pdf"),
            readableProvider(named: "third.pdf"),
        ]
        let client = client(providers)

        let report = try await client.prepare(credentials, "Photos", nil) { _ in }

        #expect(report.stagedCount == 2)
        #expect(report.failures == [ItemFailure(index: 1, name: "broken.pdf", cause: .cannotRead)])
        client.discard()
    }

    @Test("a failing item without a name is still identified by its position")
    func anUnnamedFailureGetsAPositionName() async throws {
        let client = try client([readableProvider(named: "a.pdf"), failingProvider(named: nil)])

        let report = try await client.prepare(credentials, "Photos", nil) { _ in }

        let failure = try #require(report.failures.first)
        #expect(failure.index == 1)
        #expect(!failure.name.isEmpty)
        client.discard()
    }

    @Test("an out of space failure is reported with that cause")
    func aFullDeviceIsNamedAsTheCause() async throws {
        let client = client([failingProvider(named: "big.mov", error: CocoaError(.fileWriteOutOfSpace))])

        let report = try await client.prepare(credentials, "Photos", nil) { _ in }

        #expect(report.stagedCount == 0)
        #expect(report.failures.map(\.cause) == [.notEnoughSpace])
        client.discard()
    }

    @Test("a retry pass stages only the requested items into the same batch")
    func aRetryAddsToTheSameBatch() async throws {
        let failsOnce = LockIsolated(true)
        let flaky = NSItemProvider()
        flaky.suggestedName = "flaky.pdf"
        let file = try temporaryFile(named: "flaky.pdf")
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

        let first = try await client.prepare(credentials, "Photos", nil) { _ in }
        #expect(first.stagedCount == 1)
        #expect(first.failures.map(\.index) == [1])

        let second = try await client.prepare(credentials, "Photos", [1]) { _ in }
        #expect(second.stagedCount == 2, "the earlier file is still staged")
        #expect(second.failures.isEmpty)
        client.discard()
    }

    @Test("an item with no file, such as a link, is skipped quietly")
    func aLinkIsNotAFailure() async throws {
        let link = NSItemProvider(object: URL(string: "https://example.com")! as NSURL)
        let client = client([link])

        let report = try await client.prepare(credentials, "Photos", nil) { _ in }

        #expect(report.stagedCount == 0)
        #expect(report.failures.isEmpty)
        client.discard()
    }

    @Test("progress reports the finished items and ends complete")
    func progressEndsComplete() async throws {
        let seen = LockIsolated<[PreparationProgress]>([])
        let client = try client([readableProvider(named: "a.pdf"), readableProvider(named: "b.pdf")])

        _ = try await client.prepare(credentials, "Photos", nil) { progress in
            seen.withValue { $0.append(progress) }
        }

        #expect(seen.value.last == PreparationProgress(completed: 2))
        #expect(seen.value.map(\.completed).contains(1))
        client.discard()
    }

    @Test("the Progress the provider returns drives the reported fraction")
    func theProvidersProgressIsReported() async throws {
        let file = try temporaryFile(named: "video.pdf")
        let progress = Progress(totalUnitCount: 100)
        let release = LockIsolated<(@Sendable () -> Void)?>(nil)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(for: .pdf, visibility: .all, openInPlace: false) { completion in
            nonisolated(unsafe) let finish = completion
            release.setValue { finish(file, false, nil) }
            return progress
        }
        let seen = LockIsolated<[Double]>([])
        let client = client([provider])

        let task = Task {
            try await client.prepare(credentials, "Photos", nil) { reported in
                seen.withValue { $0.append(reported.fraction) }
            }
        }
        while release.value == nil {
            await Task.yield()
        }
        // The observation attaches just after the load starts, so keep changing the value until it has been seen.
        var attempts = 0
        while !seen.value.contains(where: { $0 >= 0.5 }), attempts < 200 {
            attempts += 1
            progress.completedUnitCount = attempts.isMultiple(of: 2) ? 50 : 51
            try await Task.sleep(for: .milliseconds(10))
        }
        release.value?()
        let report = try await task.value

        #expect(seen.value.contains { $0 >= 0.5 }, "the fraction of the file being read reaches the caller")
        #expect(report.stagedCount == 1)
        client.discard()
    }

    @Test("cancelling cancels the provider's Progress, drops the batch, and throws")
    func cancellingStopsTheLoadAndDiscardsTheBatch() async throws {
        let progress = Progress(totalUnitCount: 100)
        let started = LockIsolated(false)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(for: .pdf, visibility: .all, openInPlace: false) { _ in
            started.setValue(true)
            return progress
        }
        let client = client([provider])

        let task = Task {
            try await client.prepare(credentials, "Photos", nil) { _ in }
        }
        while !started.value {
            await Task.yield()
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(progress.isCancelled, "the copy itself is stopped, not just ignored")
        #expect(throws: (any Error).self) { try client.start() }
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

    @Test("discarding with nothing staged is harmless")
    func discardWithoutABatch() {
        client([]).discard()
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

    @Test("an unknown error is reported as other, never with its raw description")
    func unknownErrorIsOther() {
        struct Odd: Error {}
        #expect(ProviderStager.cause(of: Odd()) == .other)
    }

    @Test("every cause has a message")
    func everyCauseHasAMessage() {
        for cause in [ItemFailureCause.cannotRead, .notEnoughSpace, .other] {
            #expect(!cause.message.isEmpty)
        }
    }

    @Test("a failure line names the file and the cause")
    func failureLineNamesTheFile() {
        let failure = ItemFailure(index: 3, name: "IMG_0042.MOV", cause: .notEnoughSpace)
        #expect(failure.line.contains("IMG_0042.MOV"))
        #expect(failure.line.contains(ItemFailureCause.notEnoughSpace.message))
    }
}
