import Dependencies
import Foundation
#if os(macOS)
    import AppKit
#endif

/// Opens the NextExplorer app from the share sheet, for the states the extension can't fix itself
/// (signed out, an unreadable session, a missing client certificate).
///
/// Only the Mac can: the app registers no URL scheme, and an iPhone or iPad share extension has no
/// other supported way to launch its app, so there the view shows instructions instead.
public struct OpenAppClient: Sendable {
    public var isAvailable: Bool
    public var open: @Sendable () -> Void

    public init(isAvailable: Bool, open: @escaping @Sendable () -> Void) {
        self.isAvailable = isAvailable
        self.open = open
    }
}

extension OpenAppClient: DependencyKey {
    static let appBundleIdentifier = "com.phillipmaizza.nextexplorer"

    public static var liveValue: OpenAppClient {
        #if os(macOS)
            OpenAppClient(isAvailable: true) {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleIdentifier) else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        #else
            OpenAppClient(isAvailable: false) {}
        #endif
    }

    public static let testValue = OpenAppClient(isAvailable: false) {}
    public static let previewValue = OpenAppClient(isAvailable: true) {}
}

public extension DependencyValues {
    var openApp: OpenAppClient {
        get { self[OpenAppClient.self] }
        set { self[OpenAppClient.self] = newValue }
    }
}
