import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import ShareUploads

/// The Share Extension's one screen: what is being uploaded, to which account and folder, and the
/// Upload button. With a default folder and "Upload Without Asking" set in the app's Settings it
/// starts on its own, so one tap on NextExplorer in the share sheet is all it takes.
@Reducer
public struct ShareUploadFeature {
    private enum Constants {
        /// Long enough to read "Uploading in the background" before the sheet goes.
        static let closeDelay: Duration = .seconds(1.5)
    }

    public enum Phase: Equatable, Sendable {
        case loading
        /// Signed in; checking the server answers before anything can be uploaded.
        case checking
        case signedOut
        case nothingToUpload
        case ready
        case preparing
        case started
        case failed
        /// The server wants a client certificate this device doesn't have for it, or refused the
        /// one presented. A background upload would retry that handshake for hours, so nothing
        /// is sent.
        case certificateRequired
        case certificateRejected
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var phase: Phase = .loading
        public var itemCount = 0
        public var preparedCount = 0
        public var credentials: SessionCredentials?
        /// `""` until a folder is chosen: the server refuses uploads to the root.
        public var destination = ""
        /// Settings' "Upload Without Asking" for this account: uploads once the connection checks out.
        public var uploadsWithoutAsking = false
        @Presents public var folderPicker: DestinationPickerFeature.State?

        public init() {}

        public var canUpload: Bool {
            phase == .ready && credentials != nil && !destination.isEmpty
        }

        /// "phillip on files.example.com".
        public var accountName: String {
            guard let credentials else { return "" }
            let host = credentials.serverBaseURL.host() ?? credentials.serverBaseURL.absoluteString
            guard let username = credentials.username, !username.isEmpty else { return host }
            return "\(username) · \(host)"
        }
    }

    public enum Action: Equatable {
        case onAppear
        case sessionLoaded(SessionCredentials?, UploadDefaults)
        case connectionChecked(ConnectionCheck)
        case chooseFolderTapped
        case folderPicker(PresentationAction<DestinationPickerFeature.Action>)
        case uploadTapped
        case prepared(Int)
        case uploadResponse(Result<Int, UploadFailure>)
        case cancelTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            /// The extension should close; `completed` is whether anything was handed off.
            case close(completed: Bool)
        }
    }

    public struct UploadFailure: Error, Equatable {}

    public enum ConnectionCheck: Equatable, Sendable {
        /// Signed in, or not reachable right now (the background upload waits for the network).
        case usable
        case signedOut
        case certificateRequired
        case certificateRejected
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.uploadDefaults) var uploadDefaults
    @Dependency(\.sharedItems) var sharedItems
    @Dependency(\.continuousClock) var clock

    public init() {}

    private enum CancelID { case upload }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.phase == .loading else { return .none }
                state.itemCount = sharedItems.count()
                guard state.itemCount > 0 else {
                    state.phase = .nothingToUpload
                    return .none
                }
                let authClient = authClient
                let uploadDefaults = uploadDefaults
                return .run { send in
                    let credentials = await authClient.restoreSession()
                    let defaults = credentials.map { uploadDefaults.load($0.accountID) } ?? UploadDefaults()
                    await send(.sessionLoaded(credentials, defaults))
                }

            case let .sessionLoaded(credentials, defaults):
                guard let credentials else {
                    state.phase = .signedOut
                    return .none
                }
                state.credentials = credentials
                state.destination = defaults.folderPath ?? ""
                state.uploadsWithoutAsking = defaults.directFolder != nil
                state.phase = .checking
                // Checked before anything is staged, the one tap path included: an expired session
                // or a certificate problem would otherwise leave the uploads failing in the background.
                let authClient = authClient
                return .run { send in
                    let check: ConnectionCheck
                    do {
                        _ = try await authClient.me(credentials.serverBaseURL)
                        check = .usable
                    } catch AuthClientError.sessionExpired {
                        check = .signedOut
                    } catch AuthClientError.clientCertificateRequired {
                        check = .certificateRequired
                    } catch AuthClientError.clientCertificateRejected {
                        check = .certificateRejected
                    } catch {
                        check = .usable
                    }
                    await send(.connectionChecked(check))
                }

            case let .connectionChecked(check):
                guard state.phase == .checking else { return .none }
                switch check {
                case .usable:
                    state.phase = .ready
                    return state.uploadsWithoutAsking ? .send(.uploadTapped) : .none
                case .signedOut:
                    state.phase = .signedOut
                case .certificateRequired:
                    state.phase = .certificateRequired
                case .certificateRejected:
                    state.phase = .certificateRejected
                }
                return .none

            case .chooseFolderTapped:
                guard let credentials = state.credentials, state.phase == .ready else { return .none }
                state.folderPicker = DestinationPickerFeature.State(
                    serverURL: credentials.serverBaseURL,
                    uploadStartingAt: state.destination
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

            case .uploadTapped:
                guard state.canUpload, let credentials = state.credentials else { return .none }
                state.phase = .preparing
                state.preparedCount = 0
                let destination = state.destination
                let sharedItems = sharedItems
                return .run { send in
                    do {
                        let count = try await sharedItems.upload(credentials, destination) { prepared in
                            Task { await send(.prepared(prepared)) }
                        }
                        await send(.uploadResponse(.success(count)))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.uploadResponse(.failure(UploadFailure())))
                    }
                }
                .cancellable(id: CancelID.upload, cancelInFlight: true)

            case let .prepared(count):
                state.preparedCount = max(state.preparedCount, count)
                return .none

            case .uploadResponse(.success(0)):
                state.phase = .nothingToUpload
                return .none

            case .uploadResponse(.success):
                state.phase = .started
                let clock = clock
                return .run { send in
                    try await clock.sleep(for: Constants.closeDelay)
                    await send(.delegate(.close(completed: true)))
                }

            case .uploadResponse(.failure):
                state.phase = .failed
                return .none

            case .cancelTapped:
                // Once started the uploads belong to the system: closing never stops them.
                return .merge(
                    .cancel(id: CancelID.upload),
                    .send(.delegate(.close(completed: state.phase == .started)))
                )

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$folderPicker, action: \.folderPicker) {
            DestinationPickerFeature()
        }
    }
}
