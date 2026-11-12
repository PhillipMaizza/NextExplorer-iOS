import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

@MainActor
protocol SettingsFeatureTestSupport {
}

extension SettingsFeatureTestSupport {
    typealias Store = TestStoreOf<SettingsFeature>

    var serverURL: URL { SettingsTestSupport.serverURL }
    var user: User { User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: []) }
    var admin: User { User(id: "admin-1", username: "boss", email: "boss@example.com", roles: [UserRole.admin]) }

    func makeState(user: User? = nil) -> SettingsFeature.State {
        let state = SettingsFeature.State(serverURL: serverURL, user: user ?? self.user)
        // `.inMemory` shared state is keyed by string, so every test starts from a known value
        // rather than assuming a clean default.
        state.$preferences.withLock { $0 = UserPreferences() }
        state.$branding.withLock { $0 = Branding() }
        return state
    }

    func makeStore(state: SettingsFeature.State? = nil) -> Store {
        TestStore(initialState: state ?? makeState()) { SettingsFeature() }
    }
}
