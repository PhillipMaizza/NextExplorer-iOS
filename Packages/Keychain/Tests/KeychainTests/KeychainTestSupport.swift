@testable import Keychain
import TestUtils

extension KeychainConfiguration {
    /// A service name no other test shares, so tests never see each other's real keychain items.
    static func unique() -> KeychainConfiguration {
        KeychainConfiguration(service: "app.nextplorer.tests.\(TestID.name())")
    }
}
