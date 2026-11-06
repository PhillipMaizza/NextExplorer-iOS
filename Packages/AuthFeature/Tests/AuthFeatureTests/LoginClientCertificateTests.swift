import AuthClient
@testable import AuthFeature
import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import NetworkClient
import Testing

@MainActor
@Suite("LoginFormFeature client certificates")
struct LoginClientCertificateTests {
    private let origin = ClientCertificateOrigin(host: "files.example.com", port: 8443)

    @Test("A server that wants a certificate offers the sheet, and the offer outlives the error text")
    func requiredOffersSheet() async {
        let clock = TestClock()
        let store = TestStore(initialState: LoginFormFeature.State(host: "files.example.com:8443")) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in throw AuthClientError.clientCertificateRequired }
            $0.continuousClock = clock
        }
        store.timeout = LoginFormFeatureTests.receiveTimeout

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(5))
        await store.receive(\.testConnectionResponse.failure) {
            $0.connectionPhase = .failure
            $0.errorMessage = L10n.Login.errorClientCertificateRequired
            $0.certificatePrompt = .init(origin: origin, isRejected: false)
        }
        await store.receive(\.revertToIdle) { $0.connectionPhase = .idle }
        await store.receive(\.clearErrorMessage) { $0.errorMessage = nil }

        await store.send(.clientCertificateButtonTapped) {
            $0.clientCertificate = ClientCertificateFeature.State(origin: origin)
        }
    }

    @Test("A refused certificate is told apart from a missing one")
    func rejectedPrompt() async {
        let clock = TestClock()
        let store = TestStore(initialState: LoginFormFeature.State(host: "files.example.com:8443")) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in throw AuthClientError.clientCertificateRejected }
            $0.continuousClock = clock
        }
        store.timeout = LoginFormFeatureTests.receiveTimeout
        store.exhaustivity = .off

        await store.send(.testConnectionButtonTapped)
        await clock.advance(by: .seconds(0.3))
        await store.receive(\.testConnectionResponse.failure) {
            $0.errorMessage = L10n.Login.errorClientCertificateRejected
            $0.certificatePrompt = .init(origin: origin, isRejected: true)
        }
    }

    @Test("Installing a certificate closes the sheet and retries the connection on its own")
    func installRetries() async {
        let clock = TestClock()
        let summary = ClientCertificateSummary(subject: "Dev Client")
        let status = AuthStatus(localEnabled: true, oidcEnabled: false)
        let store = TestStore(
            initialState: LoginFormFeature.State(
                host: "files.example.com:8443",
                certificatePrompt: .init(origin: origin, isRejected: false),
                clientCertificate: ClientCertificateFeature.State(origin: origin, status: .empty)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = { _ in status }
            $0.continuousClock = clock
        }
        store.timeout = LoginFormFeatureTests.receiveTimeout

        await store.send(.clientCertificate(.presented(.delegate(.installed(summary))))) {
            $0.clientCertificate = nil
            $0.certificatePrompt = nil
        }
        await store.receive(\.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.3))
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = status
        }
        await clock.advance(by: .seconds(1))
        await store.receive(\.advanceToCredentials) { $0.currentPage = .credentials }
    }

    @Test("A connection test that later succeeds drops the certificate offer")
    func successClearsPrompt() async {
        let status = AuthStatus(localEnabled: true, oidcEnabled: false)
        let store = TestStore(
            initialState: LoginFormFeature.State(
                connectionPhase: .testing,
                host: "files.example.com:8443",
                certificatePrompt: .init(origin: origin, isRejected: false)
            )
        ) {
            LoginFormFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off

        await store.send(.testConnectionResponse(.success(status))) {
            $0.certificatePrompt = nil
        }
        await store.skipInFlightEffects()
    }

    @Test("Editing the address drops the certificate offer")
    func hostChangeClearsPrompt() async {
        let store = TestStore(
            initialState: LoginFormFeature.State(
                host: "files.example.com:8443",
                certificatePrompt: .init(origin: origin, isRejected: false)
            )
        ) {
            LoginFormFeature()
        }

        await store.send(.hostChanged("files.example.com:844")) {
            $0.host = "files.example.com:844"
            $0.certificatePrompt = nil
        }
    }

    @Test("An ordinary failure never offers a certificate")
    func otherErrorsNoPrompt() {
        #expect(LoginFormFeature.certificatePrompt(for: .network("x"), scheme: .https, host: "a.com") == nil)
        #expect(LoginFormFeature.certificatePrompt(for: .rateLimited, scheme: .https, host: "a.com") == nil)
        #expect(
            LoginFormFeature.certificatePrompt(for: .clientCertificateRequired, scheme: .https, host: "A.com")
                == .init(origin: .init(host: "a.com", port: 443), isRejected: false)
        )
        #expect(
            LoginFormFeature.certificatePrompt(for: .clientCertificateRequired, scheme: .http, host: "192.168.1.5:3000")?.origin
                == .init(host: "192.168.1.5", port: 3000)
        )
    }
}
