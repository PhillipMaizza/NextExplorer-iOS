import ComposableArchitecture
import Foundation
import NetworkClient

private enum Constants {
    /// A PKCS#12 bundle is a few kilobytes. Anything past this was picked by mistake, so it is
    /// refused before it is read into memory.
    static let maxFileBytes = 1024 * 1024
}

/// Shows, installs, replaces and removes the client certificate the app presents to one server.
/// Shared by the login screen (a server that refuses the handshake) and Settings.
@Reducer
public struct ClientCertificateFeature {
    public enum Status: Equatable, Sendable {
        case loading
        case empty
        case installed(ClientCertificateSummary)
    }

    public enum Failure: Equatable, Sendable {
        case wrongPassword
        case invalidFile
        case noIdentity
        case storage
        case unreadable
        case removal

        init(_ error: ClientCertificateImportError) {
            switch error {
            case .wrongPassword: self = .wrongPassword
            case .invalidFile: self = .invalidFile
            case .noIdentity: self = .noIdentity
            case .storage: self = .storage
            }
        }
    }

    public enum ImportPhase: Equatable, Sendable {
        case idle
        case importing
        case failed(Failure)
    }

    public struct PendingFile: Equatable, Sendable {
        public var name: String
        public var data: Data

        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    @ObservableState
    public struct State: Equatable {
        public let origin: ClientCertificateOrigin
        public var status: Status
        public var pendingFile: PendingFile?
        public var passphrase: String
        public var importPhase: ImportPhase
        public var isFileImporterPresented: Bool
        public var isConfirmingRemoval: Bool

        public init(
            origin: ClientCertificateOrigin,
            status: Status = .loading,
            pendingFile: PendingFile? = nil,
            passphrase: String = "",
            importPhase: ImportPhase = .idle,
            isFileImporterPresented: Bool = false,
            isConfirmingRemoval: Bool = false
        ) {
            self.origin = origin
            self.status = status
            self.pendingFile = pendingFile
            self.passphrase = passphrase
            self.importPhase = importPhase
            self.isFileImporterPresented = isFileImporterPresented
            self.isConfirmingRemoval = isConfirmingRemoval
        }

        public var serverName: String {
            origin.port == 443 ? origin.host : "\(origin.host):\(origin.port)"
        }

        public var installedSummary: ClientCertificateSummary? {
            guard case let .installed(summary) = status else { return nil }
            return summary
        }

        public var isImporting: Bool {
            importPhase == .importing
        }

        public var failure: Failure? {
            guard case let .failed(failure) = importPhase else { return nil }
            return failure
        }

        public var canInstall: Bool {
            pendingFile != nil && !isImporting
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case statusLoaded(ClientCertificateSummary?)
        case chooseFileTapped
        case fileImporterPresentationChanged(Bool)
        case filePicked(URL)
        case fileLoaded(PendingFile?)
        case passphraseChanged(String)
        case discardFileTapped
        case installTapped
        case installResponse(Result<ClientCertificateSummary, ClientCertificateImportError>)
        case removeTapped
        case removeCancelled
        case removeConfirmed
        case removeFinished(stillInstalled: ClientCertificateSummary?)
        case closeTapped
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case installed(ClientCertificateSummary)
            case removed
        }
    }

    private enum CancelID {
        case readFile
        case install
    }

    @Dependency(\.clientCertificateClient) var clientCertificateClient
    @Dependency(\.dismiss) var dismiss

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let origin = state.origin
                return .run { [client = clientCertificateClient] send in
                    await send(.statusLoaded(client.summary(origin)))
                }

            case let .statusLoaded(summary):
                state.status = summary.map(Status.installed) ?? .empty
                return .none

            case .chooseFileTapped:
                guard !state.isImporting else { return .none }
                state.isFileImporterPresented = true
                return .none

            case let .fileImporterPresentationChanged(isPresented):
                state.isFileImporterPresented = isPresented
                return .none

            case let .filePicked(url):
                state.isFileImporterPresented = false
                return .run { send in
                    await send(.fileLoaded(Self.readFile(at: url)))
                }
                .cancellable(id: CancelID.readFile, cancelInFlight: true)

            case let .fileLoaded(file):
                guard let file else {
                    state.importPhase = .failed(.unreadable)
                    return .none
                }
                state.pendingFile = file
                state.passphrase = ""
                state.importPhase = .idle
                return .none

            case let .passphraseChanged(passphrase):
                state.passphrase = passphrase
                if case .failed(.wrongPassword) = state.importPhase {
                    state.importPhase = .idle
                }
                return .none

            case .discardFileTapped:
                // An import in flight finishes in the keychain whatever happens here, so the sheet
                // waits for it rather than pretending it was abandoned.
                guard !state.isImporting else { return .none }
                state.pendingFile = nil
                state.passphrase = ""
                state.importPhase = .idle
                return .cancel(id: CancelID.install)

            case .installTapped:
                guard let file = state.pendingFile, !state.isImporting else { return .none }
                state.importPhase = .importing
                let passphrase = state.passphrase
                let origin = state.origin
                return .run { [client = clientCertificateClient] send in
                    do {
                        let summary = try await client.install(file.data, passphrase, origin)
                        await send(.installResponse(.success(summary)))
                    } catch let error as ClientCertificateImportError {
                        await send(.installResponse(.failure(error)))
                    } catch {
                        await send(.installResponse(.failure(.storage)))
                    }
                }
                .cancellable(id: CancelID.install, cancelInFlight: true)

            case let .installResponse(.success(summary)):
                state.status = .installed(summary)
                state.pendingFile = nil
                state.passphrase = ""
                state.importPhase = .idle
                return .send(.delegate(.installed(summary)))

            case let .installResponse(.failure(error)):
                state.importPhase = .failed(Failure(error))
                return .none

            case .removeTapped:
                state.isConfirmingRemoval = true
                return .none

            case .removeCancelled:
                state.isConfirmingRemoval = false
                return .none

            case .removeConfirmed:
                state.isConfirmingRemoval = false
                let origin = state.origin
                return .run { [client = clientCertificateClient] send in
                    await client.remove(origin)
                    await send(.removeFinished(stillInstalled: client.summary(origin)))
                }

            case let .removeFinished(stillInstalled):
                if let stillInstalled {
                    state.status = .installed(stillInstalled)
                    state.importPhase = .failed(.removal)
                    return .none
                }
                state.status = .empty
                return .send(.delegate(.removed))

            case .closeTapped:
                guard !state.isImporting else { return .none }
                return .run { [dismiss] _ in await dismiss() }

            case .delegate:
                return .none
            }
        }
    }

    /// Reads a picked file inside its security scope. Runs in an effect, off the main actor.
    static func readFile(at url: URL) -> PendingFile? {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= Constants.maxFileBytes,
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return PendingFile(name: url.lastPathComponent, data: data)
    }
}
