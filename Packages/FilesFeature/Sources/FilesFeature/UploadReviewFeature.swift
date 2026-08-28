import ComposableArchitecture
import Foundation
import Localization
import PhotosUI
import SwiftUI

/// The sheet shown after files are picked, before they're queued: the file list, the
/// destination folder (tap to push the folder picker), the total size, and the Upload button.
/// It never uploads — confirming hands `(files, destination)` up to `BrowseFeature`.
///
/// The sheet is presented *immediately* on pick and fills in as files are materialized by
/// `UploadStagingClient` (copied out of the picker, photos read into memory). Staging runs as
/// a cancellable effect owned here, so dismissing the sheet stops it and `BrowseFeature`
/// discards whatever already landed.
@Reducer
public struct UploadReviewFeature {
    /// One pick's worth of raw picker output, before it's been copied anywhere.
    public enum PickSource: Equatable, Sendable {
        case documents([URL])
        case photos([PhotosPickerItem])
        case camera(URL)

        var count: Int {
            switch self {
            case let .documents(urls): urls.count
            case let .photos(items): items.count
            case .camera: 1
            }
        }
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var serverURL: URL
        public var files: IdentifiedArrayOf<PickedFile>
        /// Files still being copied out of the picker. `files` grows as each lands.
        public var preparingCount: Int
        /// `true` when the last staging batch produced nothing and there's nothing else
        /// pending — the sheet stays open showing an error rather than vanishing.
        public var stagingFailed = false
        /// `""` means no folder chosen yet (the pick started at the root) — Upload stays
        /// disabled until the user picks one.
        public var destination: String
        @Presents public var folderPicker: DestinationPickerFeature.State?

        public init(serverURL: URL, files: [PickedFile] = [], startingDestination: String, preparingCount: Int = 0) {
            self.serverURL = serverURL
            self.files = IdentifiedArray(uniqueElements: files)
            self.destination = startingDestination
            self.preparingCount = preparingCount
        }

        public var isPreparing: Bool { preparingCount > 0 }
        /// Total files the sheet is about, including ones still being prepared.
        public var totalCount: Int { files.count + preparingCount }
        public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
        public var canUpload: Bool { !isPreparing && !files.isEmpty && !destination.isEmpty }
        public var hasDestination: Bool { !destination.isEmpty }
    }

    public enum Action: Equatable, Sendable {
        /// Begin (or add to) staging for one pick. Bumps `preparingCount`, then streams each
        /// copied file back as `filePrepared`.
        case stage(PickSource)
        case filePrepared(PickedFile)
        /// One `stage` batch drained: `requested` items asked for, `staged` actually copied.
        case stagingBatchFinished(requested: Int, staged: Int)
        case pathTapped
        case folderPicker(PresentationAction<DestinationPickerFeature.Action>)
        case removeFileTapped(id: PickedFile.ID)
        case uploadTapped
        case cancelTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case confirmed(files: [PickedFile], destination: String)
            case cancelled
        }
    }

    @Dependency(\.uploadStaging) var uploadStaging
    private enum CancelID { case staging }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .stage(source):
                let requested = source.count
                guard requested > 0 else { return .none }
                state.stagingFailed = false
                state.preparingCount += requested
                let uploadStaging = self.uploadStaging
                return .run { send in
                    var staged = 0
                    switch source {
                    case let .documents(urls):
                        for await file in uploadStaging.stageDocuments(urls) {
                            staged += 1
                            await send(.filePrepared(file), animation: .default)
                        }
                    case let .photos(items):
                        for await file in uploadStaging.stagePhotos(items) {
                            staged += 1
                            await send(.filePrepared(file), animation: .default)
                        }
                    case let .camera(url):
                        if let file = await uploadStaging.stageCameraCapture(url) {
                            staged += 1
                            await send(.filePrepared(file), animation: .default)
                        }
                    }
                    await send(.stagingBatchFinished(requested: requested, staged: staged))
                }
                .cancellable(id: CancelID.staging)

            case let .filePrepared(file):
                state.files.append(file)
                state.preparingCount = max(0, state.preparingCount - 1)
                state.stagingFailed = false
                return .none

            case let .stagingBatchFinished(requested, staged):
                // Items that failed to stage never arrive as `filePrepared`; drop them here.
                state.preparingCount = max(0, state.preparingCount - max(0, requested - staged))
                guard state.files.isEmpty, state.preparingCount == 0 else { return .none }
                if staged == 0, requested > 0 {
                    state.stagingFailed = true
                    return .none
                }
                return .send(.delegate(.cancelled))

            case .pathTapped:
                state.folderPicker = DestinationPickerFeature.State(
                    serverURL: state.serverURL, uploadStartingAt: state.destination
                )
                return .none

            case let .folderPicker(.presented(.delegate(.confirmed(destination)))):
                state.destination = destination
                state.folderPicker = nil
                return .none

            case .folderPicker(.presented(.delegate(.cancelled))):
                state.folderPicker = nil
                return .none

            case .folderPicker:
                return .none

            case let .removeFileTapped(id):
                let removed = state.files[id: id]?.fileURL
                state.files.remove(id: id)
                let uploadStaging = self.uploadStaging
                let discardEffect: Effect<Action> = removed.map { url in
                    .run { _ in await uploadStaging.discard([url]) }
                } ?? .none
                if state.files.isEmpty, !state.isPreparing {
                    return .merge(discardEffect, .send(.delegate(.cancelled)))
                }
                return discardEffect

            case .uploadTapped:
                guard state.canUpload else { return .none }
                return .send(.delegate(.confirmed(files: Array(state.files), destination: state.destination)))

            case .cancelTapped:
                return .send(.delegate(.cancelled))

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$folderPicker, action: \.folderPicker) {
            DestinationPickerFeature()
        }
    }
}
