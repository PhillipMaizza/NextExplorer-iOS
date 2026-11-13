import Foundation
import Security

/// The App Group the app and its Share Extension share: the folder background uploads are staged
/// in, and the defaults the upload settings live in.
///
/// iOS uses `group.com.phillipmaizza.nextexplorer`. The Mac uses the team prefixed form
/// (`<team>.com.phillipmaizza.nextexplorer`), which the sandbox grants from the entitlement alone;
/// a `group.` identifier there also needs it in the provisioning profile, and without that every
/// write to the group is refused.
public enum AppGroup {
    /// `nil` when this build isn't entitled to the group (unsigned, tests, a profile without it):
    /// callers then use the process's own storage.
    public static let identifier: String? = {
        #if os(macOS)
            guard
                let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
                !prefix.isEmpty, !prefix.hasPrefix("$(")
            else { return nil }
            let group = prefix + "com.phillipmaizza.nextexplorer"
            // The Mac hands out a container path whether or not the process may use it.
            return isEntitled(to: group) ? group : nil
        #else
            let group = "group.com.phillipmaizza.nextexplorer"
            return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) == nil ? nil : group
        #endif
    }()

    public static var containerURL: URL? {
        identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    public static var defaults: UserDefaults {
        identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    #if os(macOS)
        private static func isEntitled(to group: String) -> Bool {
            guard
                let task = SecTaskCreateFromSelf(nil),
                let value = SecTaskCopyValueForEntitlement(
                    task,
                    "com.apple.security.application-groups" as CFString,
                    nil
                )
            else { return false }
            return (value as? [String])?.contains(group) ?? false
        }
    #endif
}
