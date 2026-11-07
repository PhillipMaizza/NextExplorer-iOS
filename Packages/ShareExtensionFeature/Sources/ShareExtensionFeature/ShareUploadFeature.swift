import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient
import ShareUploads

/// The Share Extension's one screen: what is being uploaded, to which account and folder, and the
/// Upload button. With a default folder and "Upload Without Asking" set in the app's Settings it
/// starts on its own, so one tap on NextExplorer in the share sheet is all it takes.
@Reducer
public struct ShareUploadFeature {
    private enum Constants {
        /// Long enough to read "Uploading in the background" before the sheet goes.
        static let closeDelay: Duration = .seconds(1.5)
        /// With VoiceOver or Switch Control running, long enough to hear the result and act on it.
        static let assistiveCloseDelay: Duration = .seconds(8)
        static let notFoundStatusCode = 404
    }

    public enum Phase: Hashable, Sendable {
        case loading
        /// Signed in; checking the server answers before anything can be uploaded.
        case checking
        case signedOut
        /// The keychain holds a session this process could not read, which is not the same as
        /// being signed out: opening the app once usually repairs it.
        case sessionUnreadable
        case nothingToUpload
        case ready
        case preparing
        /// Everything is staged and being handed to the system. Closing no longer discards: the
        /// uploads may already be running.
        case handingOff
        /// Some files staged and some did not. The staged batch waits for the user to upload it or
        /// retry the others.
        case partiallyPrepared
        case started
        case failed
        /// The server wants a client certificate this device doesn't have for it, or refused the
        /// one presented. A background upload would retry that handshake for hours, so nothing
        /// is sent.
        case certificateRequired
        case certificateRejected
    }

    /// Something to tell the user next to the folder they are about to choose.
    public enum Notice: Equatable, Sendable {
        case defaultFolderUnavailable
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var phase: Phase = .loading
        public var itemCount = 0
        /// How many of them are Live Photos, whose motion video goes along with the still.
        public var livePhotoCount = 0
        /// How many items the running preparation pass reads (a retry reads only the failures).
        public var preparingTotal = 0
        public var progress = PreparationProgress()
        /// How many files are staged and waiting, across every pass.
        public var stagedCount = 0
        /// The items the last pass could not prepare, by name.
        public var failures: [ItemFailure] = []
        public var notice: Notice?
        public var credentials: SessionCredentials?
        /// Every signed in account, to pick which one receives the files.
        public var accounts: [SessionCredentials] = []
        /// `""` until a folder is chosen: the server refuses uploads to the root.
        public var destination = ""
        /// Settings' "Upload Without Asking" for this account: uploads once the connection checks out.
        public var shouldUploadWithoutAsking = false
        @Presents public var folderPicker: DestinationPickerFeature.State?

        public init() {}

        public var canUpload: Bool {
            phase == .ready && credentials != nil && !destination.isEmpty
        }

        public var accountName: String {
            credentials.map(Self.name(for:)) ?? ""
        }

        public var serverName: String {
            credentials.map { $0.serverBaseURL.host() ?? $0.serverBaseURL.absoluteString } ?? ""
        }

        /// Several accounts are signed in: the account row becomes a picker.
        public var canChooseAccount: Bool {
            accounts.count > 1 && [.checking, .ready, .signedOut, .certificateRequired, .certificateRejected].contains(phase)
        }

        /// How much of the running preparation pass is done, 0 to 1.
        public var preparationFraction: Double {
            guard preparingTotal > 0 else { return 0 }
            return min(1, (Double(progress.completed) + progress.fraction) / Double(preparingTotal))
        }

        /// Whether the account and folder rows are shown: while uploading, and read only after a
        /// failed or partial pass, so the user still sees where the files were going.
        public var shouldShowDetails: Bool {
            [.checking, .ready, .preparing, .handingOff, .started, .partiallyPrepared, .failed].contains(phase)
        }

        /// Work is in flight and the main button shows a spinner instead of accepting taps.
        public var isWorking: Bool {
            [.checking, .preparing, .handingOff].contains(phase)
        }

        /// The item the running preparation pass is reading, counting from 1.
        public var preparingStep: Int {
            min(progress.completed + 1, preparingTotal)
        }

        /// What the footer's main button does in this phase, or `nil` when it has none. Return and
        /// the prominent button follow it. A state only the app can fix offers opening it where
        /// that is possible (the Mac) and nothing but the instruction where it is not.
        public func primaryAction(canOpenApp: Bool) -> Control? {
            switch phase {
            case .checking, .ready, .preparing, .handingOff: .upload
            case .partiallyPrepared: .uploadReady
            case .failed: .retry
            case .signedOut, .sessionUnreadable, .certificateRequired, .certificateRejected: canOpenApp ? .openApp : nil
            case .loading, .nothingToUpload, .started: nil
            }
        }

        public func secondaryAction(canOpenApp: Bool) -> Control? {
            switch phase {
            case .partiallyPrepared: .retryFailed
            case .signedOut, .sessionUnreadable, .certificateRequired, .certificateRejected: canOpenApp ? .retry : nil
            case .loading, .checking, .nothingToUpload, .ready, .preparing, .handingOff, .started, .failed: nil
            }
        }

        /// "phillip · files.example.com".
        public static func name(for credentials: SessionCredentials) -> String {
            let host = credentials.serverBaseURL.host() ?? credentials.serverBaseURL.absoluteString
            guard let username = credentials.username, !username.isEmpty else { return host }
            return L10n.ShareUpload.accountSummary(username, host)
        }
    }

    /// A button the footer can offer.
    public enum Control: Equatable, Sendable {
        case upload
        case uploadReady
        case retryFailed
        case retry
        case openApp

        var action: Action {
            switch self {
            case .upload: .uploadTapped
            case .uploadReady: .uploadReadyTapped
            case .retryFailed, .retry: .retryTapped
            case .openApp: .openAppTapped
            }
        }
    }

    public enum Action: Equatable {
        case onAppear
        case sessionLoaded(SessionCredentials?, UploadDefaults)
        case sessionUnreadable
        case accountsLoaded([SessionCredentials])
        case accountSelected(String)
        case connectionChecked(accountID: String, ConnectionCheck)
        case defaultFolderChecked(accountID: String, DefaultFolderCheck)
        case chooseFolderTapped
        case folderPicker(PresentationAction<DestinationPickerFeature.Action>)
        case uploadTapped
        case progressed(PreparationProgress)
        case preparationFinished(Result<PreparationReport, UploadFailure>)
        case uploadReadyTapped
        case uploadResponse(Result<Int, UploadFailure>)
        case retryTapped
        case openAppTapped
        case cancelTapped
        case viewDisappeared
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

    public enum DefaultFolderCheck: Equatable, Sendable {
        /// The folder is there and takes uploads, or it can't be told right now (offline).
        case usable
        /// Deleted, moved, or no longer open to uploads for this account.
        case unavailable
        case signedOut
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.filesClient) var filesClient
    @Dependency(\.uploadDefaults) var uploadDefaults
    @Dependency(\.sharedItems) var sharedItems
    @Dependency(\.continuousClock) var clock
    @Dependency(\.cookieStorage) var cookieStorage
    @Dependency(\.openApp) var openApp
    @Dependency(\.shareAccessibility) var accessibility

    public init() {}

    private enum CancelID { case upload, connection, folder, close }

    /// Reads the session again, from a state that has none (first appearance, Try Again).
    private func loadSession() -> Effect<Action> {
        let authClient = authClient
        let uploadDefaults = uploadDefaults
        return .run { send in
            do {
                let credentials = try await authClient.loadSession()
                let defaults = credentials.map { uploadDefaults.load($0.accountID) } ?? UploadDefaults()
                await send(.accountsLoaded(authClient.listSessions()))
                await send(.sessionLoaded(credentials, defaults))
            } catch {
                await send(.sessionUnreadable)
            }
        }
    }

    /// Checked before anything is staged, the one tap path included: an expired session or a
    /// certificate problem would otherwise leave the uploads failing in the background.
    private func checkConnection(_ credentials: SessionCredentials) -> Effect<Action> {
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
            await send(.connectionChecked(accountID: credentials.accountID, check))
        }
        .cancellable(id: CancelID.connection, cancelInFlight: true)
    }

    /// Once, before an automatic upload: a default folder deleted or moved since it was chosen
    /// would otherwise fail every file in the background.
    private func checkDefaultFolder(_ credentials: SessionCredentials, path: String) -> Effect<Action> {
        let filesClient = filesClient
        return .run { send in
            let check: DefaultFolderCheck
            do {
                let listing = try await filesClient.browse(credentials.serverBaseURL, path)
                check = listing.access.canUpload ? .usable : .unavailable
            } catch FilesClientError.server(statusCode: Constants.notFoundStatusCode),
                FilesClientError.serverMessage(statusCode: Constants.notFoundStatusCode, _),
                FilesClientError.forbidden
            {
                check = .unavailable
            } catch FilesClientError.sessionExpired {
                check = .signedOut
            } catch {
                if Task.isCancelled {
                    return
                }
                check = .usable
            }
            await send(.defaultFolderChecked(accountID: credentials.accountID, check))
        }
        .cancellable(id: CancelID.folder, cancelInFlight: true)
    }

    private func prepare(
        _ state: inout State,
        credentials: SessionCredentials,
        indexes: [Int]?
    ) -> Effect<Action> {
        state.phase = .preparing
        state.failures = []
        state.progress = PreparationProgress()
        state.preparingTotal = indexes?.count ?? state.itemCount
        let destination = state.destination
        let sharedItems = sharedItems
        return .run { send in
            do {
                let report = try await sharedItems.prepare(credentials, destination, indexes) { progress in
                    Task { await send(.progressed(progress)) }
                }
                await send(.preparationFinished(.success(report)))
            } catch {
                // A cancellation nobody asked for (the pass gave up on its own) is a failure; one
                // the store asked for (closing the sheet) is not.
                if Task.isCancelled {
                    return
                }
                await send(.preparationFinished(.failure(UploadFailure())))
            }
        }
        .cancellable(id: CancelID.upload, cancelInFlight: true)
    }

    private func startBatch() -> Effect<Action> {
        let sharedItems = sharedItems
        return .run { send in
            do {
                try await send(.uploadResponse(.success(sharedItems.start())))
            } catch {
                await send(.uploadResponse(.failure(UploadFailure())))
            }
        }
    }

    private func discardBatch() -> Effect<Action> {
        let sharedItems = sharedItems
        return .run { _ in sharedItems.discard() }
    }

    private func announce(_ message: String) -> Effect<Action> {
        let accessibility = accessibility
        return .run { _ in accessibility.announce(message) }
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.phase == .loading else { return .none }
                state.itemCount = sharedItems.count()
                state.livePhotoCount = sharedItems.livePhotoCount()
                guard state.itemCount > 0 else {
                    state.phase = .nothingToUpload
                    return .none
                }
                return loadSession()

            case let .accountsLoaded(accounts):
                state.accounts = accounts
                return .none

            case let .accountSelected(accountID):
                guard state.canChooseAccount, accountID != state.credentials?.accountID,
                      let credentials = state.accounts.first(where: { $0.accountID == accountID })
                else { return .none }
                let defaults = uploadDefaults.load(accountID)
                state.credentials = credentials
                state.destination = defaults.folderPath ?? ""
                state.notice = nil
                // Picking an account is a choice in itself: it never uploads on its own.
                state.shouldUploadWithoutAsking = false
                state.phase = .checking
                // This extension's own cookie jar only: the app's active account stays as it is.
                if let cookie = credentials.httpCookie {
                    cookieStorage.setCookie(cookie)
                }
                return .merge(.cancel(id: CancelID.folder), checkConnection(credentials))

            case let .sessionLoaded(credentials, defaults):
                guard let credentials else {
                    state.phase = .signedOut
                    return .none
                }
                state.credentials = credentials
                state.destination = defaults.folderPath ?? ""
                state.shouldUploadWithoutAsking = defaults.directFolder != nil
                state.phase = .checking
                return checkConnection(credentials)

            case .sessionUnreadable:
                state.phase = .sessionUnreadable
                return announce(L10n.ShareUpload.sessionUnreadable)

            case let .connectionChecked(accountID, check):
                guard state.phase == .checking, state.credentials?.accountID == accountID else { return .none }
                switch check {
                case .usable:
                    guard state.shouldUploadWithoutAsking, let credentials = state.credentials else {
                        state.phase = .ready
                        return .none
                    }
                    // Still checking: the folder has to be there before anything goes out.
                    return checkDefaultFolder(credentials, path: state.destination)
                case .signedOut:
                    state.phase = .signedOut
                case .certificateRequired:
                    state.phase = .certificateRequired
                case .certificateRejected:
                    state.phase = .certificateRejected
                }
                return .none

            case let .defaultFolderChecked(accountID, check):
                guard state.phase == .checking, state.credentials?.accountID == accountID else { return .none }
                switch check {
                case .usable:
                    state.phase = .ready
                    return .send(.uploadTapped)
                case .unavailable:
                    state.phase = .ready
                    state.destination = ""
                    state.shouldUploadWithoutAsking = false
                    state.notice = .defaultFolderUnavailable
                    guard let credentials = state.credentials else { return .none }
                    state.folderPicker = DestinationPickerFeature.State(
                        serverURL: credentials.serverBaseURL,
                        uploadStartingAt: ""
                    )
                    return announce(L10n.ShareUpload.defaultFolderUnavailable)
                case .signedOut:
                    state.phase = .signedOut
                    return .none
                }

            case .chooseFolderTapped:
                guard let credentials = state.credentials, state.phase == .ready else { return .none }
                state.folderPicker = DestinationPickerFeature.State(
                    serverURL: credentials.serverBaseURL,
                    uploadStartingAt: state.destination
                )
                return .none

            case let .folderPicker(.presented(.delegate(.confirmed(destination)))):
                state.destination = destination
                state.notice = nil
                state.folderPicker = nil
                return .none

            case .folderPicker(.presented(.delegate(.cancelled))):
                state.folderPicker = nil
                return .none

            case .folderPicker:
                return .none

            case .uploadTapped:
                guard state.canUpload, let credentials = state.credentials else { return .none }
                state.notice = nil
                return prepare(&state, credentials: credentials, indexes: nil)

            case let .progressed(progress):
                guard state.phase == .preparing else { return .none }
                let isNewer = (progress.completed, progress.fraction) > (state.progress.completed, state.progress.fraction)
                if isNewer {
                    state.progress = progress
                }
                return .none

            case let .preparationFinished(.success(report)):
                guard state.phase == .preparing else { return .none }
                state.stagedCount = report.stagedCount
                state.failures = report.failures
                guard report.failures.isEmpty else {
                    state.phase = report.stagedCount > 0 ? .partiallyPrepared : .failed
                    return announce(L10n.ShareUpload.failedItemsHeader)
                }
                guard report.stagedCount > 0 else {
                    state.phase = .nothingToUpload
                    return discardBatch()
                }
                state.phase = .handingOff
                return startBatch()

            case .preparationFinished(.failure):
                guard state.phase == .preparing else { return .none }
                state.phase = .failed
                state.failures = []
                return .merge(discardBatch(), announce(L10n.ShareUpload.failed))

            case .uploadReadyTapped:
                guard state.phase == .partiallyPrepared else { return .none }
                // The hand off is quick but not instant: no second tap may start it twice.
                state.phase = .handingOff
                state.progress = PreparationProgress(completed: state.preparingTotal)
                return startBatch()

            case .uploadResponse where state.phase != .handingOff:
                return .none

            case .uploadResponse(.success(0)):
                state.phase = .nothingToUpload
                return .none

            case .uploadResponse(.success):
                state.phase = .started
                let isAssistive = accessibility.isAssistiveTechnologyRunning()
                let delay = isAssistive ? Constants.assistiveCloseDelay : Constants.closeDelay
                let clock = clock
                return .merge(
                    announce(L10n.ShareUpload.started),
                    .run { send in
                        try await clock.sleep(for: delay)
                        await send(.delegate(.close(completed: true)))
                    }
                    .cancellable(id: CancelID.close, cancelInFlight: true)
                )

            case .uploadResponse(.failure):
                state.phase = .failed
                state.failures = []
                return announce(L10n.ShareUpload.failed)

            case .retryTapped:
                switch state.phase {
                case .signedOut, .sessionUnreadable:
                    state.phase = .loading
                    state.credentials = nil
                    state.accounts = []
                    return loadSession()
                case .certificateRequired, .certificateRejected:
                    guard let credentials = state.credentials else { return .none }
                    state.phase = .checking
                    return checkConnection(credentials)
                case .failed, .partiallyPrepared:
                    guard let credentials = state.credentials else { return .none }
                    let indexes = state.failures.isEmpty ? nil : state.failures.map(\.index)
                    // Without named failures the whole pass failed: start over on a clean batch, once
                    // the old one is gone.
                    return .concatenate(
                        indexes == nil ? discardBatch() : .none,
                        prepare(&state, credentials: credentials, indexes: indexes)
                    )
                case .loading, .checking, .nothingToUpload, .ready, .preparing, .handingOff, .started:
                    return .none
                }

            case .openAppTapped:
                let openApp = openApp
                return .run { _ in openApp.open() }

            case .cancelTapped:
                // The hand off finishes within moments and the sheet closes itself after it: a
                // close now would race the start and could cut it short.
                guard state.phase != .handingOff else { return .none }
                // Once started the uploads belong to the system: closing never stops them.
                return .merge(
                    .cancel(id: CancelID.upload),
                    .cancel(id: CancelID.close),
                    state.hasStagedFiles ? discardBatch() : .none,
                    .send(.delegate(.close(completed: state.phase == .started)))
                )

            case .viewDisappeared:
                guard state.hasStagedFiles else { return .cancel(id: CancelID.close) }
                return .merge(.cancel(id: CancelID.upload), .cancel(id: CancelID.close), discardBatch())

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$folderPicker, action: \.folderPicker) {
            DestinationPickerFeature()
        }
    }
}

extension ShareUploadFeature.State {
    /// A batch may be staged on disk that nothing has started yet.
    var hasStagedFiles: Bool {
        [.preparing, .partiallyPrepared, .failed].contains(phase)
    }
}
