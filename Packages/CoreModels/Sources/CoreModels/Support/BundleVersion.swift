import Foundation

public extension Bundle {
    var marketingVersion: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var buildNumber: String? {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
