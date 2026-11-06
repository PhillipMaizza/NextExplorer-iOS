import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing

@Suite(.dependencies)
@MainActor
struct SettingsClientCertificateTests {
    private let serverURL = URL(string: "https://files.example.com:8443")!
    private let origin = ClientCertificateOrigin(host: "files.example.com", port: 8443)
    private let user = User(id: "1", username: "jdoe", email: nil, roles: [])
    private let summary = ClientCertificateSummary(subject: "Dev Client")

    @Test("The row shows the installed certificate for this server")
    func loadsStatusOnAppear() async {
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: user)) {
            SettingsFeature()
        } withDependencies: { [origin, summary] in
            $0.clientCertificateClient = .inMemory([origin: summary])
            $0.filesClient.fetchPreferences = { _ in UserPreferences() }
            $0.filesClient.fetchBranding = { _ in Branding() }
            $0.filesClient.serverFeatures = { _ in ServerFeatures() }
            $0.localDownloadStore.list = { _ in [] }
            $0.previewCacheStore.size = { 0 }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.clientCertificateStatusLoaded) {
            $0.clientCertificateStatus = .installed(summary)
        }
    }

    @Test("Tapping the row opens the sheet for this server, seeded with what is known")
    func opensSheet() async {
        var state = SettingsFeature.State(serverURL: serverURL, user: user)
        state.clientCertificateStatus = .empty
        let store = TestStore(initialState: state) { SettingsFeature() }

        await store.send(.clientCertificateButtonTapped) {
            $0.clientCertificate = ClientCertificateFeature.State(origin: origin, status: .empty)
        }
    }

    @Test("Installing and removing in the sheet keep the row in step")
    func delegateUpdatesRow() async {
        var state = SettingsFeature.State(serverURL: serverURL, user: user)
        state.clientCertificateStatus = .empty
        state.clientCertificate = ClientCertificateFeature.State(origin: origin, status: .empty)
        let store = TestStore(initialState: state) { SettingsFeature() }

        await store.send(.clientCertificate(.presented(.delegate(.installed(summary))))) {
            $0.clientCertificateStatus = .installed(summary)
        }
        await store.send(.clientCertificate(.presented(.delegate(.removed)))) {
            $0.clientCertificateStatus = .empty
        }
    }

    @Test("The row value reads the certificate name, None, or nothing while loading")
    func rowDetail() {
        #expect(ClientCertificateFeature.Status.loading.settingsDetail.isEmpty)
        #expect(ClientCertificateFeature.Status.installed(summary).settingsDetail == "Dev Client")
        #expect(!ClientCertificateFeature.Status.empty.settingsDetail.isEmpty)
    }
}
