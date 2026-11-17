import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import Localization

/// Restoring from the trash, shared by the trash list and a deleted folder: asks what to do with
/// the share links when there are any, picks a folder for Restore To, runs the request, and words
/// the result. The owner reloads when it hears `delegate(.finished)`.
@Reducer
public struct TrashRestoreFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        /// A restore waiting for the user to choose what happens to its share links.
        public var awaitingShareChoice: Request?
        /// Restore To: the target waiting for the folder picker's answer.
        public var awaitingDestination: Request?
        @Presents public var destinationPicker: DestinationPickerFeature.State?
        public var phase: Phase = .idle
        public var notice: TrashNotice?
        /// What the last restore brought back, for the toast's Undo to move to the trash again.
        public var undoable: [FileItem] = []

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        public var isRestoring: Bool {
            phase != .idle
        }
    }

    /// A restore in place is quick; one into a chosen folder copies, reports how far it is (`nil`
    /// until the server says) and can be stopped.
    public enum Phase: Equatable, Sendable {
        case idle
        case inPlace
        case toFolder(progress: Double?)
    }

    public struct Request: Equatable, Sendable {
        public let target: TrashTarget
        public var destination: String?
        public let shareCount: Int
    }

    public enum Action: Equatable, Sendable {
        case restore(TrashTarget, shareCount: Int)
        case restoreTo(TrashTarget, shareCount: Int)
        case destinationPicker(PresentationAction<DestinationPickerFeature.Action>)
        case shareChoiceMade(ShareLinkChoice)
        case shareChoiceDismissed
        case cancelTapped
        case progressed(Double)
        case undoTapped
        case undoResponse(Result<DeleteOutcome, FilesClientError>)
        case response(Result<TrashActionResult, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            /// Something may have left the trash: reload.
            case finished
        }
    }

    enum CancelID {
        case restore, undo
    }

    @Dependency(\.filesClient) var filesClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .restore(target, shareCount):
                return ask(&state, Request(target: target, destination: nil, shareCount: shareCount))

            case let .restoreTo(target, shareCount):
                guard !state.isRestoring else { return .none }
                state.awaitingDestination = Request(target: target, destination: nil, shareCount: shareCount)
                state.destinationPicker = DestinationPickerFeature.State(serverURL: state.serverURL, restoringFrom: "")
                return .none

            case let .destinationPicker(.presented(.delegate(.confirmed(destination)))):
                state.destinationPicker = nil
                guard var request = state.awaitingDestination else { return .none }
                state.awaitingDestination = nil
                request.destination = destination
                return ask(&state, request)

            case .destinationPicker(.presented(.delegate(.cancelled))):
                state.destinationPicker = nil
                state.awaitingDestination = nil
                return .none

            case .destinationPicker:
                return .none

            case let .shareChoiceMade(choice):
                guard let request = state.awaitingShareChoice else { return .none }
                state.awaitingShareChoice = nil
                return run(&state, request, shares: choice)

            case .shareChoiceDismissed:
                state.awaitingShareChoice = nil
                return .none

            case .cancelTapped:
                // Closing the request stops the server; what had not started stays in the trash.
                guard state.isRestoring else { return .none }
                state.phase = .idle
                return .merge(.cancel(id: CancelID.restore), .send(.delegate(.finished)))

            case let .progressed(fraction):
                guard case .toFolder = state.phase else { return .none }
                state.phase = .toFolder(progress: fraction)
                return .none

            case let .response(.success(result)):
                state.phase = .idle
                state.undoable = Self.restoredItems(in: result)
                state.notice = TrashNotice.after(
                    state.notice,
                    text: Self.summary(of: result),
                    isFailure: result.succeeded.isEmpty,
                    isUndoable: !state.undoable.isEmpty
                )
                return .send(.delegate(.finished))

            case .undoTapped:
                guard !state.isRestoring, !state.undoable.isEmpty else { return .none }
                let items = state.undoable
                state.undoable = []
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .run { send in
                    try await send(.undoResponse(apiResult {
                        try await filesClient.deleteItems(serverURL, items, false, nil)
                    }))
                }
                .cancellable(id: CancelID.undo, cancelInFlight: true)

            case let .undoResponse(.success(outcome)):
                let moved = outcome.trashedCount
                state.notice = TrashNotice.after(
                    state.notice,
                    text: moved > 0 ? L10n.Trash.movedToTrash(moved) : L10n.Trash.failureUnknown,
                    isFailure: moved == 0
                )
                return .send(.delegate(.finished))

            case let .undoResponse(.failure(error)):
                state.notice = TrashNotice.after(state.notice, text: error.userMessage, isFailure: true)
                return .send(.delegate(.finished))

            case let .response(.failure(error)):
                state.phase = .idle
                state.undoable = []
                state.notice = TrashNotice.after(state.notice, text: error.userMessage, isFailure: true)
                return .send(.delegate(.finished))

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$destinationPicker, action: \.destinationPicker) {
            DestinationPickerFeature()
        }
    }

    private func ask(_ state: inout State, _ request: Request) -> Effect<Action> {
        guard !state.isRestoring else { return .none }
        guard request.shareCount == 0 else {
            state.awaitingShareChoice = request
            return .none
        }
        // Nothing to bring back; the choice is sent anyway, since the server needs one.
        return run(&state, request, shares: .drop)
    }

    private func run(_ state: inout State, _ request: Request, shares: ShareLinkChoice) -> Effect<Action> {
        state.phase = request.destination == nil ? .inPlace : .toFolder(progress: nil)
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            let result = try await apiResult {
                try await withProgressActions(send: send, action: Action.progressed) { onProgress in
                    try await filesClient.restoreTrash(
                        serverURL,
                        request.target,
                        request.destination,
                        shares,
                        onProgress
                    )
                }
            }
            await send(.response(result))
        }
        .cancellable(id: CancelID.restore, cancelInFlight: true)
    }

    /// The restored items as Browse addresses them (parent folder and name), for Undo. An item the
    /// server gave no folder for (one this user cannot open) cannot be sent back.
    static func restoredItems(in result: TrashActionResult) -> [FileItem] {
        result.succeeded.compactMap { entry in
            guard let parent = entry.path, let name = entry.restoredName ?? entry.name else { return nil }
            return FileItem(name: name, path: parent, dateModified: .distantPast, size: 0, kind: "")
        }
    }

    /// Counts, renamed items, share links and failures, one line each.
    static func summary(of result: TrashActionResult) -> String {
        var lines: [String] = []
        if !result.succeeded.isEmpty {
            lines.append(L10n.Trash.restored(result.succeeded.count))
        }
        for entry in result.succeeded where entry.isRenamed {
            lines.append(L10n.Trash.renamed(entry.name ?? "", entry.restoredName ?? ""))
        }
        if result.sharesRestored > 0 {
            lines.append(L10n.Trash.sharesRestored(result.sharesRestored))
        }
        if result.sharesDropped > 0 {
            lines.append(L10n.Trash.sharesDropped(result.sharesDropped))
        }
        if let failure = result.failed.first {
            lines.append(L10n.Trash.notRestored(result.failed.count) + " " + failure.status.reason)
        }
        return lines.joined(separator: "\n")
    }
}

/// A result to show once as a toast: `sequence` makes a repeat of the same text show again.
public struct TrashNotice: Equatable, Sendable {
    public let text: String
    public let isFailure: Bool
    /// A restore the toast offers to undo.
    public var isUndoable = false
    public let sequence: Int

    static func after(
        _ previous: TrashNotice?,
        text: String,
        isFailure: Bool,
        isUndoable: Bool = false
    ) -> TrashNotice {
        TrashNotice(text: text, isFailure: isFailure, isUndoable: isUndoable, sequence: (previous?.sequence ?? 0) + 1)
    }
}

extension TrashActionResult.Status {
    /// Why an item could not be restored or deleted, as one sentence.
    var reason: String {
        switch self {
        case .forbidden: L10n.Trash.failureForbidden
        case .destinationForbidden: L10n.Trash.failureDestinationForbidden
        case .blocked: L10n.Trash.failureBlocked
        case .invalidDestination: L10n.Trash.failureInvalidDestination
        case .unavailable: L10n.Trash.failureUnavailable
        case .busy: L10n.Trash.failureBusy
        case .lost: L10n.Trash.failureLost
        case .notFound: L10n.Trash.failureNotFound
        case .cancelled: L10n.Trash.failureCancelled
        case .restored, .purged, .forgotten, .unknown: L10n.Trash.failureUnknown
        }
    }
}
