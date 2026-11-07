import Foundation

/// The App Group the app and its Share Extension share: the folder background uploads are staged
/// in, and the defaults the upload settings live in.
public enum AppGroup {
    public static let identifier = "group.com.phillipmaizza.nextexplorer"

    /// `nil` in a build without the App Group entitlement (unsigned, tests): callers fall back to
    /// the process's own storage.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static var defaults: UserDefaults {
        containerURL == nil ? .standard : UserDefaults(suiteName: identifier) ?? .standard
    }
}
