import CoreModels
import Foundation

/// The launch environment XCUITest sets, readable by every feature package (the app's
/// `UITestSupport` wires the mocked graph from the same keys). Always off in Release.
public enum UITestEnvironment {
    public static let mockKey = UITestLaunchKey.mock.rawValue
    public static let disableAnimationsKey = UITestLaunchKey.disableAnimations.rawValue
    public static let on = UITestLaunchKey.on

    /// Whether this launch runs under the mocked XCUITest graph.
    public static let isActive: Bool = {
        #if DEBUG
            ProcessInfo.processInfo.environment[mockKey] == on
        #else
            false
        #endif
    }()
}
