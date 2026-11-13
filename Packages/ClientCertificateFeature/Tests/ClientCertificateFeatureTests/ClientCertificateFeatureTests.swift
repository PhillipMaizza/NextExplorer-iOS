@testable import ClientCertificateFeature
import ComposableArchitecture
import Foundation
import NetworkClient
import Testing
import TestUtils

@MainActor
@Suite("ClientCertificateFeature", .isolatedDependencies)
struct ClientCertificateFeatureTests {
    private let origin = ClientCertificateOrigin(host: TestHost.server, port: 8443)
    private let summary = ClientCertificateSummary(subject: TestCertificate.subject, issuer: "Dev CA", expiresAt: nil)
    private let file = ClientCertificateFeature.PendingFile(name: Constants.certificateFileName, data: Data([1, 2, 3]))

    @Test("Appearing loads what is installed")
    func loadsStatus() async {
        let store = TestStore(initialState: ClientCertificateFeature.State(origin: origin)) {
            ClientCertificateFeature()
        } withDependencies: {
            $0.clientCertificateClient = .inMemory([origin: summary])
        }

        await store.send(.onAppear)
        await store.receive(\.statusLoaded) {
            $0.status = .installed(summary)
        }
    }

    @Test("Nothing installed shows the empty state")
    func loadsEmpty() async {
        let store = TestStore(initialState: ClientCertificateFeature.State(origin: origin)) {
            ClientCertificateFeature()
        } withDependencies: {
            $0.clientCertificateClient = .inMemory()
        }

        await store.send(.onAppear)
        await store.receive(\.statusLoaded) {
            $0.status = .empty
        }
    }

    @Test("A picked file asks for its password, and installing reports to the parent")
    func installFlow() async {
        let installed = LockIsolated<(Data, String, ClientCertificateOrigin)?>(nil)
        let store = TestStore(initialState: ClientCertificateFeature.State(origin: origin, status: .empty)) {
            ClientCertificateFeature()
        } withDependencies: { [summary] in
            $0.clientCertificateClient.install = { data, passphrase, origin in
                installed.setValue((data, passphrase, origin))
                return summary
            }
        }

        await store.send(.chooseFileTapped) {
            $0.isFileImporterPresented = true
        }
        await store.send(.fileLoaded(file)) {
            $0.pendingFile = file
        }
        await store.send(.passphraseChanged(Constants.passphrase)) {
            $0.passphrase = Constants.passphrase
        }
        await store.send(.installTapped) {
            $0.importPhase = .importing
        }
        await store.receive(\.installResponse) {
            $0.status = .installed(summary)
            $0.pendingFile = nil
            $0.passphrase = ""
            $0.importPhase = .idle
        }
        await store.receive(\.delegate, .installed(summary))
        #expect(installed.value?.0 == file.data)
        #expect(installed.value?.1 == Constants.passphrase)
        #expect(installed.value?.2 == origin)
    }

    @Test("A wrong password keeps the file and clears once the user edits it")
    func wrongPassword() async {
        let store = TestStore(
            initialState: ClientCertificateFeature.State(
                origin: origin,
                status: .empty,
                pendingFile: file,
                passphrase: TestAccount.rejectedPassword
            )
        ) {
            ClientCertificateFeature()
        } withDependencies: {
            $0.clientCertificateClient.install = { _, _, _ in throw ClientCertificateImportError.wrongPassword }
        }

        await store.send(.installTapped) {
            $0.importPhase = .importing
        }
        await store.receive(\.installResponse) {
            $0.importPhase = .failed(.wrongPassword)
        }
        #expect(store.state.pendingFile == file)
        #expect(store.state.canInstall)
        await store.send(.passphraseChanged(Constants.secondRejectedPassphrase)) {
            $0.passphrase = Constants.secondRejectedPassphrase
            $0.importPhase = .idle
        }
    }

    @Test("A file without a key is reported as such")
    func noIdentity() async {
        let store = TestStore(
            initialState: ClientCertificateFeature.State(origin: origin, status: .empty, pendingFile: file)
        ) {
            ClientCertificateFeature()
        } withDependencies: {
            $0.clientCertificateClient.install = { _, _, _ in throw ClientCertificateImportError.noIdentity }
        }

        await store.send(.installTapped) {
            $0.importPhase = .importing
        }
        await store.receive(\.installResponse) {
            $0.importPhase = .failed(.noIdentity)
        }
    }

    @Test("An unreadable file surfaces an error and keeps nothing pending")
    func unreadableFile() async {
        let store = TestStore(initialState: ClientCertificateFeature.State(origin: origin, status: .empty)) {
            ClientCertificateFeature()
        }

        await store.send(.fileLoaded(nil)) {
            $0.importPhase = .failed(.unreadable)
        }
        #expect(store.state.pendingFile == nil)
        #expect(!store.state.canInstall)
    }

    @Test("Installing twice while the first is running is ignored")
    func doubleInstall() async {
        let store = TestStore(
            initialState: ClientCertificateFeature.State(
                origin: origin,
                status: .empty,
                pendingFile: file,
                importPhase: .importing
            )
        ) {
            ClientCertificateFeature()
        }

        await store.send(.installTapped)
    }

    @Test("Removing asks first, then clears the certificate")
    func removeFlow() async {
        let removed = LockIsolated<ClientCertificateOrigin?>(nil)
        let store = TestStore(
            initialState: ClientCertificateFeature.State(origin: origin, status: .installed(summary))
        ) {
            ClientCertificateFeature()
        } withDependencies: {
            $0.clientCertificateClient.remove = { removed.setValue($0) }
        }

        await store.send(.removeTapped) {
            $0.isConfirmingRemoval = true
        }
        await store.send(.removeCancelled) {
            $0.isConfirmingRemoval = false
        }
        await store.send(.removeTapped) {
            $0.isConfirmingRemoval = true
        }
        await store.send(.removeConfirmed) {
            $0.isConfirmingRemoval = false
        }
        await store.receive(\.removeFinished) {
            $0.status = .empty
        }
        await store.receive(\.delegate, .removed)
        #expect(removed.value == origin)
    }

    @Test("A removal the keychain refused keeps showing the certificate, with an error")
    func failedRemoval() async {
        let store = TestStore(
            initialState: ClientCertificateFeature.State(
                origin: origin,
                status: .installed(summary),
                isConfirmingRemoval: true
            )
        ) {
            ClientCertificateFeature()
        } withDependencies: { [origin, summary] in
            $0.clientCertificateClient = .inMemory([origin: summary])
            $0.clientCertificateClient.remove = { _ in }
        }

        await store.send(.removeConfirmed) {
            $0.isConfirmingRemoval = false
        }
        await store.receive(\.removeFinished) {
            $0.importPhase = .failed(.removal)
        }
    }

    @Test("Closing, discarding or picking again waits while an import is running")
    func busyWhileImporting() async {
        let store = TestStore(
            initialState: ClientCertificateFeature.State(
                origin: origin,
                status: .empty,
                pendingFile: file,
                importPhase: .importing
            )
        ) {
            ClientCertificateFeature()
        }

        await store.send(.closeTapped)
        await store.send(.discardFileTapped)
        await store.send(.chooseFileTapped)
    }

    @Test("Discarding a picked file returns to the overview")
    func discardFile() async {
        let store = TestStore(
            initialState: ClientCertificateFeature.State(
                origin: origin, status: .empty, pendingFile: file, passphrase: "x", importPhase: .failed(.wrongPassword)
            )
        ) {
            ClientCertificateFeature()
        }

        await store.send(.discardFileTapped) {
            $0.pendingFile = nil
            $0.passphrase = ""
            $0.importPhase = .idle
        }
    }

    @Test("Reading a real file keeps its name and bytes, and a huge one is refused")
    func readFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: TestID.name())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let small = directory.appending(path: Constants.certificateFileName)
        try Data([9, 8, 7]).write(to: small)
        let huge = directory.appending(path: "huge.p12")
        try Data(count: 2 * 1024 * 1024).write(to: huge)

        #expect(ClientCertificateFeature.readFile(at: small) == .init(
            name: Constants.certificateFileName,
            data: Data([9, 8, 7])
        ))
        #expect(ClientCertificateFeature.readFile(at: huge) == nil)
        #expect(ClientCertificateFeature.readFile(at: directory.appending(path: "missing.p12")) == nil)
    }

    @Test("The server name hides the default port")
    func serverName() {
        #expect(ClientCertificateFeature.State(origin: .init(host: TestHost.shortHost, port: 443))
            .serverName == TestHost.shortHost)
        #expect(ClientCertificateFeature.State(origin: origin).serverName == TestHost.serverWithPort)
    }
}

private enum Constants {
    static let certificateFileName = "dev.p12"
    static let passphrase = "secret"
    static let secondRejectedPassphrase = "nope2"
}
