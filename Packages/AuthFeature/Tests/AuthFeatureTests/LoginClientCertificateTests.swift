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
@Suite("LoginFormFeature client certificates", .serialized)
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
            $0.certificateInUse = summary
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

    @Test("An http address the server redirects to https signs in over https")
    func httpRedirectSwitchesToHTTPS() async {
        let status = AuthStatus(localEnabled: true, oidcEnabled: false, redirectsToHTTPS: true)
        let store = TestStore(initialState: LoginFormFeature.State(connectionPhase: .testing, host: "files.example.com")) {
            LoginFormFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off
        await store.send(.schemeChanged(.http))
        await store.send(.testConnectionResponse(.success(status))) {
            $0.scheme = .https
        }
        await store.skipInFlightEffects()
    }

    @Test(
        "A redirect to https carries the answered port, not the typed one",
        arguments: [
            ("files.example.com:8080", nil as Int?, "files.example.com"),
            ("files.example.com:8080", 9443, "files.example.com:9443"),
            ("files.example.com:8443", 8443, "files.example.com:8443"),
            ("files.example.com", nil as Int?, "files.example.com"),
            ("files.example.com", 8443, "files.example.com:8443"),
            ("http://files.example.com:8080/path", nil as Int?, "files.example.com"),
            ("[::1]:8080", 9443, "[::1]:9443"),
            ("192.168.1.5:3000", nil as Int?, "192.168.1.5"),
        ]
    )
    func httpRedirectCarriesThePort(typed: String, answeredPort: Int?, expected: String) async {
        let status = AuthStatus(localEnabled: true, oidcEnabled: false, redirectsToHTTPS: true, redirectedPort: answeredPort)
        let store = TestStore(initialState: LoginFormFeature.State(connectionPhase: .testing, host: typed)) {
            LoginFormFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off
        await store.send(.schemeChanged(.http))
        await store.send(.testConnectionResponse(.success(status)))
        #expect(store.state.scheme == .https)
        #expect(store.state.host == expected)
        await store.skipInFlightEffects()
    }

    @Test("Without a redirect the typed host and port stay as they are")
    func noRedirectKeepsTheTypedAddress() async {
        let status = AuthStatus(localEnabled: true, oidcEnabled: false, redirectsToHTTPS: false, redirectedPort: 9443)
        let store = TestStore(initialState: LoginFormFeature.State(connectionPhase: .testing, host: "files.example.com:8080")) {
            LoginFormFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off
        await store.send(.schemeChanged(.http))
        await store.send(.testConnectionResponse(.success(status)))
        #expect(store.state.scheme == .http)
        #expect(store.state.host == "files.example.com:8080")
        await store.skipInFlightEffects()
    }

    @Test("A redirect on a host that isn't a valid address leaves the field alone")
    func redirectOnAnInvalidHostKeepsIt() async {
        let status = AuthStatus(localEnabled: true, oidcEnabled: false, redirectsToHTTPS: true, redirectedPort: 9443)
        let store = TestStore(initialState: LoginFormFeature.State(connectionPhase: .testing, host: "not a host")) {
            LoginFormFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off
        await store.send(.testConnectionResponse(.success(status)))
        #expect(store.state.host == "not a host")
        await store.skipInFlightEffects()
    }

    @Test("A server with a certificate in use shows it, and Change opens the sheet for it")
    func certificateInUseAndChange() async {
        let clock = TestClock()
        let summary = ClientCertificateSummary(subject: "Dev Client")
        let status = AuthStatus(localEnabled: true, oidcEnabled: false)
        let store = TestStore(initialState: LoginFormFeature.State(host: "files.example.com:8443")) {
            LoginFormFeature()
        } withDependencies: { [origin] in
            $0.authClient.fetchStatus = { _ in status }
            $0.continuousClock = clock
            $0.clientCertificateClient = .inMemory([origin: summary])
        }
        store.timeout = LoginFormFeatureTests.receiveTimeout

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.3))
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = status
        }
        await store.receive(\.certificateInUseLoaded) {
            $0.certificateInUse = summary
        }
        await store.send(.changeClientCertificateTapped) {
            $0.clientCertificate = ClientCertificateFeature.State(origin: origin, status: .installed(summary))
        }
        await store.send(.clientCertificate(.presented(.delegate(.removed)))) {
            $0.certificateInUse = nil
        }
        await clock.advance(by: .seconds(1))
        await store.receive(\.advanceToCredentials) { $0.currentPage = .credentials }
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
        #expect(store.state.certificateInUse == nil)
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
