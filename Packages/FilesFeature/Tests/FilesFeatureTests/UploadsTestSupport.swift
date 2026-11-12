import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

struct UploadsUploadCall: Equatable, Sendable {
    let fileURL: URL
    let fileName: String
    let destination: String
}

@MainActor
protocol UploadsTestSupport {
    var uploadCalls: LockIsolated<[UploadsUploadCall]> { get }
    var discarded: LockIsolated<[URL]> { get }
    var sweeps: LockIsolated<Int> { get }
}

extension UploadsTestSupport {
    typealias Store = TestStoreOf<UploadsFeature>
    typealias State = UploadsFeature.State
    typealias Job = UploadsFeature.UploadJob

    typealias UploadCall = UploadsUploadCall

    var serverURL: URL {
        SettingsTestSupport.serverURL
    }

    var now: Date {
        MockDate.date
    }

    nonisolated func pending(_ name: String, _ id: Int, destination: String = TestFolder.inbox) -> PendingUpload {
        PendingUpload(id: UUID(id), fileURL: URL(fileURLWithPath: "/staging/\(name)"), fileName: name, destination: destination)
    }

    nonisolated func fileURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/staging/\(name)")
    }

    nonisolated func uploaded(_ name: String, destination: String = TestFolder.inbox) -> FileItem {
        FileItem(name: name, path: destination, dateModified: MockDate.date, size: 10, kind: TestKind.text)
    }

    nonisolated func job(
        _ name: String, _ id: Int, _ status: Job.Status,
        destination: String = TestFolder.inbox, isTransportFailure: Bool = false, autoRetryCount: Int = 0, startedAt: Date? = nil
    ) -> Job {
        Job(
            id: UUID(id), fileURL: URL(fileURLWithPath: "/staging/\(name)"), fileName: name,
            destination: destination, progress: status == .completed ? 1 : 0, status: status,
            startedAt: startedAt, isTransportFailure: isTransportFailure, autoRetryCount: autoRetryCount
        )
    }

    nonisolated func summary(
        uploaded: Int, failed: Int, lastDestination: String?, changedPaths: Set<String>
    ) -> UploadsFeature.FinishSummary {
        UploadsFeature.FinishSummary(
            uploadedCount: uploaded, failedCount: failed,
            lastDestination: lastDestination, changedPaths: changedPaths
        )
    }

    func state(_ jobs: [Job] = [], isSheetPresented: Bool = false) -> State {
        var state = State(serverURL: serverURL)
        state.jobs = IdentifiedArray(uniqueElements: jobs)
        state.isSheetPresented = isSheetPresented
        return state
    }

    func makeStore(
        _ state: State,
        isSourcePresent: Bool = true,
        upload: @escaping @Sendable (UploadCall, @Sendable (Double) -> Void) async throws -> FileItem = { call, _ in
            FileItem(name: call.fileName, path: call.destination, dateModified: MockDate.date, size: 10, kind: TestKind.text)
        }
    ) -> Store {
        let uploadCalls = uploadCalls
        let discarded = discarded
        let sweeps = sweeps
        let date = now
        return TestStore(initialState: state) {
            UploadsFeature()
        } withDependencies: {
            $0.date = .constant(date)
            $0.filesClient.uploadFile = { _, url, name, destination, progress in
                let call = UploadCall(fileURL: url, fileName: name, destination: destination)
                uploadCalls.withValue { $0.append(call) }
                return try await upload(call, progress)
            }
            $0.uploadStaging = UploadStagingClient(
                stageDocuments: { _ in AsyncStream<PickedFile> { $0.finish() } },
                stagePhotos: { _ in AsyncStream<PickedFile> { $0.finish() } },
                stageCameraCapture: { _ in nil },
                discard: { urls in discarded.withValue { $0.append(contentsOf: urls) } },
                sweepStale: { sweeps.withValue { $0 += 1 } },
                sourceExists: { _ in isSourcePresent }
            )
        }
    }

    func markUploading(_ state: inout State, _ id: Int) {
        state.jobs[id: UUID(id)]?.status = .uploading
        state.jobs[id: UUID(id)]?.startedAt = now
    }

    func markCompleted(_ state: inout State, _ id: Int) {
        state.jobs[id: UUID(id)]?.status = .completed
        state.jobs[id: UUID(id)]?.progress = 1
    }

    func markFailed(_ state: inout State, _ id: Int, _ message: String, isTransportFailure: Bool = false) {
        state.jobs[id: UUID(id)]?.status = .failed(message)
        state.jobs[id: UUID(id)]?.isTransportFailure = isTransportFailure
    }
}
