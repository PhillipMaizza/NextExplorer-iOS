import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SettingsClientCertificateTests {
    private let serverURL: URL
    private let origin = ClientCertificateOrigin(host: TestHost.server, port: 8443)
    private let user = User(id: "1", username: "jdoe", email: nil, roles: [])
    private let summary = ClientCertificateSummary(subject: TestCertificate.subject)

    init() throws {
        serverURL = try #require(URL(string: "https://files.example.com:8443"))
    }

    private func state(
        status: ClientCertificateFeature.Status = .empty,
        sheet: ClientCertificateFeature.State? = nil
    ) -> SettingsFeature.State {
        var state = SettingsFeature.State(serverURL: serverURL, user: user)
        state.clientCertificateStatus = status
        state.clientCertificate = sheet
        return state
    }

    private func makeStore(_ state: SettingsFeature.State) -> TestStoreOf<SettingsFeature> {
        TestStore(initialState: state) { SettingsFeature() }
    }

    // The appearance fan out (downloads, caches, offline size, certificate, preferences, branding) starts
    // several effects whose answers arrive in no fixed order, so the lookup itself is covered by the
    // origin the reducer derives and by delivering its answer, not by running `onAppear` end to end.

    @Test
    func theRowLooksTheCertificateUpForThisServersHostAndPort() {
        #expect(ClientCertificateOrigin(url: serverURL) == origin)
    }

    @Test("The row shows the installed certificate for this server, or None when there is none")
    func theLookupAnswerFillsTheRow() async {
        let store = makeStore(state(status: .loading))

        await store.send(.clientCertificateStatusLoaded(summary)) { $0.clientCertificateStatus = .installed(summary) }
        await store.send(.clientCertificateStatusLoaded(nil)) { $0.clientCertificateStatus = .empty }
    }

    @Test("Tapping the row opens the sheet for this server, seeded with what is known")
    func opensSheet() async {
        let store = makeStore(state(status: .empty))

        await store.send(.clientCertificateButtonTapped) {
            $0.clientCertificate = ClientCertificateFeature.State(origin: origin, status: .empty)
        }
    }

    @Test("Tapping the row seeds the sheet with an installed certificate")
    func opensSheetWithInstalledCertificate() async {
        let store = makeStore(state(status: .installed(summary)))

        await store.send(.clientCertificateButtonTapped) {
            $0.clientCertificate = ClientCertificateFeature.State(origin: origin, status: .installed(summary))
        }
    }

    @Test("Installing and removing in the sheet keep the row in step")
    func delegateUpdatesRow() async {
        let store = makeStore(state(sheet: ClientCertificateFeature.State(origin: origin, status: .empty)))

        await store.send(.clientCertificate(.presented(.delegate(.installed(summary))))) {
            $0.clientCertificateStatus = .installed(summary)
        }
        await store.send(.clientCertificate(.presented(.delegate(.removed)))) {
            $0.clientCertificateStatus = .empty
        }
    }

    struct DetailCase: Sendable {
        let status: ClientCertificateFeature.Status
        let expected: String
    }

    private nonisolated static let day: TimeInterval = 24 * 60 * 60
    private nonisolated static let warningWindow: TimeInterval = 14 * day

    private nonisolated static func installed(expiringIn interval: TimeInterval?) -> ClientCertificateFeature.Status {
        .installed(ClientCertificateSummary(
            subject: TestCertificate.subject,
            expiresAt: interval.map { MockDate.date.addingTimeInterval($0) }
        ))
    }

    @Test(
        "The row value reads the certificate name, None, a warning, or nothing while loading",
        arguments: [
            DetailCase(status: .loading, expected: ""),
            DetailCase(status: .empty, expected: L10n.Settings.clientCertificateNone),
            DetailCase(status: installed(expiringIn: nil), expected: TestCertificate.subject),
            DetailCase(status: installed(expiringIn: 90 * day), expected: TestCertificate.subject),
            DetailCase(status: installed(expiringIn: warningWindow + 1), expected: TestCertificate.subject),
            DetailCase(
                status: installed(expiringIn: warningWindow),
                expected: L10n.Settings.clientCertificateExpiresSoon
            ),
            DetailCase(status: installed(expiringIn: 3 * day), expected: L10n.Settings.clientCertificateExpiresSoon),
            DetailCase(status: installed(expiringIn: 1), expected: L10n.Settings.clientCertificateExpiresSoon),
            DetailCase(status: installed(expiringIn: 0), expected: L10n.Settings.clientCertificateExpired),
            DetailCase(status: installed(expiringIn: -day), expected: L10n.Settings.clientCertificateExpired),
        ]
    )
    func rowDetail(_ testCase: DetailCase) {
        #expect(testCase.status.settingsDetail(now: MockDate.date) == testCase.expected)
    }
}
