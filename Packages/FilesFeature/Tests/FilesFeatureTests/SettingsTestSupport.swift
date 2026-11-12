import Foundation

/// Values the admin settings screens' tests share.
enum SettingsTestSupport {
    static let serverURL: URL = {
        guard let url = URL(string: "https://files.example.com") else {
            preconditionFailure("The test server URL literal is valid")
        }
        return url
    }()
}
