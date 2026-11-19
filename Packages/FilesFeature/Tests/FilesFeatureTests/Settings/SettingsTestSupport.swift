import Foundation
import TestUtils

/// Values the admin settings screens' tests share.
enum SettingsTestSupport {
    static let serverURL: URL = {
        guard let url = URL(string: TestHost.serverURLString) else {
            preconditionFailure("The test server URL literal is valid")
        }
        return url
    }()
}
