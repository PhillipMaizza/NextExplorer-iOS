import Foundation

public extension Bundle {
    /// The version people see, such as `1.4.0`; `nil` when the bundle carries none.
    var marketingVersion: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The build number; `nil` when the bundle carries none.
    var buildNumber: String? {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
