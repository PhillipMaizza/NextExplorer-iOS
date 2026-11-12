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
    private typealias Store = TestStore<LoginFormFeature.State, LoginFormFeature.Action>

    private let origin = ClientCertificateOrigin(host: "files.example.com", port: 8443)
    private let summary = ClientCertificateSummary(subject: "Dev Client")
    private let passwordOnly = AuthStatus(localEnabled: true, oidcEnabled: false)

    private func makeStore(
        _ state: LoginFormFeature.State,
        clock: TestClock<Duration>,
        certificates: [ClientCertificateOrigin: ClientCertificateSummary] = [:],
        fetchStatus: @escaping @Sendable (URL) async throws -> AuthStatus = { _ in throw AuthClientError.network("unused") }
    ) -> Store {
        TestStore(initialState: state) {
            LoginFormFeature()
        } withDependencies: {
            $0.authClient.fetchStatus = fetchStatus
            $0.continuousClock = clock
            $0.clientCertificateClient = .inMemory(certificates)
        }
    }

    /// Lets a successful connection test run its success beat and move on to the credentials page.
    private func finishSuccessBeat(_ store: Store, clock: TestClock<Duration>) async {
        await clock.advance(by: .seconds(0.5))
        await store.receive(\.advanceToCredentials) { $0.currentPage = .credentials }
    }

    struct CertificateFailure: Sendable {
        let error: AuthClientError
        let message: String
        let isRejected: Bool
    }

    nonisolated static let failures = [
        CertificateFailure(
            error: .clientCertificateRequired,
            message: L10n.Login.errorClientCertificateRequired,
            isRejected: false
        ),
        CertificateFailure(
            error: .clientCertificateRejected,
            message: L10n.Login.errorClientCertificateRejected,
            isRejected: true
        ),
    ]

    @Test("A server that wants or refuses a certificate offers the sheet, and the offer outlives the error text", arguments: failures)
    func certificateFailureOffersSheet(_ failure: CertificateFailure) async {
        let clock = TestClock()
        let store = makeStore(
            LoginFormFeature.State(host: "files.example.com:8443"),
            clock: clock,
            fetchStatus: { _ in throw failure.error }
        )

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.failure) {
            $0.connectionPhase = .failure
            $0.errorMessage = failure.message
            $0.certificatePrompt = .init(origin: origin, isRejected: failure.isRejected)
        }
        await clock.advance(by: .seconds(1))
        await store.receive(\.revertToIdle) { $0.connectionPhase = .idle }
        await clock.advance(by: .seconds(3))
        await store.receive(\.clearErrorMessage) { $0.errorMessage = nil }

        await store.send(.clientCertificateButtonTapped) {
            $0.clientCertificate = ClientCertificateFeature.State(origin: origin)
        }
    }

    @Test("Installing a certificate closes the sheet and retries the connection on its own")
    func installRetries() async {
        let clock = TestClock()
        let store = makeStore(
            LoginFormFeature.State(
                host: "files.example.com:8443",
                certificatePrompt: .init(origin: origin, isRejected: false),
                clientCertificate: ClientCertificateFeature.State(origin: origin, status: .empty)
            ),
            clock: clock,
            fetchStatus: { [passwordOnly] _ in passwordOnly }
        )

        await store.send(.clientCertificate(.presented(.delegate(.installed(summary))))) {
            $0.clientCertificate = nil
            $0.certificatePrompt = nil
            $0.certificateInUse = summary
        }
        await store.receive(\.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = passwordOnly
        }
        await finishSuccessBeat(store, clock: clock)
    }

    @Test("A connection test that later succeeds drops the certificate offer")
    func successClearsPrompt() async {
        let clock = TestClock()
        let store = makeStore(
            LoginFormFeature.State(
                connectionPhase: .testing,
                host: "files.example.com:8443",
                certificatePrompt: .init(origin: origin, isRejected: false)
            ),
            clock: clock
        )

        await store.send(.testConnectionResponse(.success(passwordOnly))) {
            $0.authStatus = passwordOnly
            $0.certificatePrompt = nil
            $0.connectionPhase = .success
        }
        await finishSuccessBeat(store, clock: clock)
    }

    struct RedirectCase: Sendable {
        let typed: String
        let answeredPort: Int?
        let expected: String
    }

    @Test(
        "A redirect to https carries the answered port, not the typed one",
        arguments: [
            RedirectCase(typed: "files.example.com:8080", answeredPort: nil, expected: "files.example.com"),
            RedirectCase(typed: "files.example.com:8080", answeredPort: 9443, expected: "files.example.com:9443"),
            RedirectCase(typed: "files.example.com:8443", answeredPort: 8443, expected: "files.example.com:8443"),
            RedirectCase(typed: "files.example.com", answeredPort: nil, expected: "files.example.com"),
            RedirectCase(typed: "files.example.com", answeredPort: 8443, expected: "files.example.com:8443"),
            RedirectCase(typed: "http://files.example.com:8080/path", answeredPort: nil, expected: "files.example.com"),
            RedirectCase(typed: "[::1]:8080", answeredPort: 9443, expected: "[::1]:9443"),
            RedirectCase(typed: "192.168.1.5:3000", answeredPort: nil, expected: "192.168.1.5"),
        ]
    )
    func httpRedirectCarriesThePort(_ testCase: RedirectCase) async {
        let clock = TestClock()
        let status = AuthStatus(localEnabled: true, oidcEnabled: false, redirectsToHTTPS: true, redirectedPort: testCase.answeredPort)
        let store = makeStore(
            LoginFormFeature.State(connectionPhase: .testing, scheme: .http, host: testCase.typed),
            clock: clock
        )

        await store.send(.testConnectionResponse(.success(status))) {
            $0.authStatus = status
            $0.scheme = .https
            $0.host = testCase.expected
            $0.connectionPhase = .success
        }
        await finishSuccessBeat(store, clock: clock)
    }

    @Test("Without a redirect the typed host and port stay as they are")
    func noRedirectKeepsTheTypedAddress() async {
        let clock = TestClock()
        let status = AuthStatus(localEnabled: true, oidcEnabled: false, redirectsToHTTPS: false, redirectedPort: 9443)
        let store = makeStore(
            LoginFormFeature.State(connectionPhase: .testing, scheme: .http, host: "files.example.com:8080"),
            clock: clock
        )

        await store.send(.testConnectionResponse(.success(status))) {
            $0.authStatus = status
            $0.connectionPhase = .success
        }
        await finishSuccessBeat(store, clock: clock)
    }

    @Test("A redirect on a host that isn't a valid address switches to https but leaves the field alone")
    func redirectOnAnInvalidHostKeepsIt() async {
        let clock = TestClock()
        let status = AuthStatus(localEnabled: true, oidcEnabled: false, redirectsToHTTPS: true, redirectedPort: 9443)
        let store = makeStore(
            LoginFormFeature.State(connectionPhase: .testing, scheme: .http, host: "not a host"),
            clock: clock
        )

        await store.send(.testConnectionResponse(.success(status))) {
            $0.authStatus = status
            $0.scheme = .https
            $0.connectionPhase = .success
        }
        await finishSuccessBeat(store, clock: clock)
    }

    @Test("A server with a certificate in use shows it, and Change opens the sheet for it")
    func certificateInUseAndChange() async {
        let clock = TestClock()
        let store = makeStore(
            LoginFormFeature.State(host: "files.example.com:8443"),
            clock: clock,
            certificates: [origin: summary],
            fetchStatus: { [passwordOnly] _ in passwordOnly }
        )

        await store.send(.testConnectionButtonTapped) { $0.connectionPhase = .testing }
        await clock.advance(by: .seconds(0.25))
        await store.receive(\.testConnectionResponse.success) {
            $0.connectionPhase = .success
            $0.authStatus = passwordOnly
        }
        await store.receive(\.certificateInUseLoaded) { $0.certificateInUse = summary }
        await store.send(.changeClientCertificateTapped) {
            $0.clientCertificate = ClientCertificateFeature.State(origin: origin, status: .installed(summary))
        }
        await store.send(.clientCertificate(.presented(.delegate(.removed)))) {
            $0.certificateInUse = nil
        }
        await finishSuccessBeat(store, clock: clock)
    }

    @Test("Editing the address drops the certificate offer and the certificate in use")
    func hostChangeClearsPrompt() async {
        let store = makeStore(
            LoginFormFeature.State(
                host: "files.example.com:8443",
                certificatePrompt: .init(origin: origin, isRejected: false),
                certificateInUse: summary
            ),
            clock: TestClock()
        )

        await store.send(.hostChanged("files.example.com:844")) {
            $0.host = "files.example.com:844"
            $0.certificatePrompt = nil
            $0.certificateInUse = nil
        }
    }

    @Test("The text field re-reporting the same address keeps the certificate offer")
    func unchangedHostKeepsPrompt() async {
        let store = makeStore(
            LoginFormFeature.State(
                host: "files.example.com:8443",
                certificatePrompt: .init(origin: origin, isRejected: false)
            ),
            clock: TestClock()
        )

        await store.send(.hostChanged("files.example.com:8443"))
    }

    struct PromptCase: Sendable {
        let error: AuthClientError
        let scheme: LoginFormFeature.URLScheme
        let host: String
        let expected: LoginFormFeature.CertificatePrompt?
    }

    @Test(
        "Only certificate failures on a valid address offer a certificate, keyed by the lowercased host and port",
        arguments: [
            PromptCase(error: .network("x"), scheme: .https, host: "a.com", expected: nil),
            PromptCase(error: .rateLimited, scheme: .https, host: "a.com", expected: nil),
            PromptCase(error: .clientCertificateRequired, scheme: .https, host: "not a host", expected: nil),
            PromptCase(
                error: .clientCertificateRequired,
                scheme: .https,
                host: "A.com",
                expected: .init(origin: .init(host: "a.com", port: 443), isRejected: false)
            ),
            PromptCase(
                error: .clientCertificateRejected,
                scheme: .https,
                host: "a.com",
                expected: .init(origin: .init(host: "a.com", port: 443), isRejected: true)
            ),
            PromptCase(
                error: .clientCertificateRequired,
                scheme: .http,
                host: "192.168.1.5:3000",
                expected: .init(origin: .init(host: "192.168.1.5", port: 3000), isRejected: false)
            ),
        ]
    )
    func certificatePrompt(_ testCase: PromptCase) {
        #expect(LoginFormFeature.certificatePrompt(for: testCase.error, scheme: testCase.scheme, host: testCase.host) == testCase.expected)
    }
}
