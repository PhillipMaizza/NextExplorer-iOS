import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// The launch environment XCUITest sets, readable by every feature package (the app's
/// `UITestSupport` wires the mocked graph from the same keys). Always off in Release.
public enum UITestEnvironment {
    public static let mockKey = "UITEST_MOCK"
    public static let disableAnimationsKey = "UITEST_DISABLE_ANIMATIONS"
    public static let on = "1"

    /// Whether this launch runs under the mocked XCUITest graph.
    public static let isActive: Bool = {
        #if DEBUG
            ProcessInfo.processInfo.environment[mockKey] == on
        #else
            false
        #endif
    }()
}

#if os(iOS)
    public typealias CredentialContentType = UITextContentType
#elseif os(macOS)
    public typealias CredentialContentType = NSTextContentType
#endif

public extension View {
    /// `textContentType` for a username or password field. Under UI tests it is dropped: iOS
    /// otherwise offers to save the password after a sign in, in a sheet the next keyboard covers,
    /// which took the tests' taps. The app itself always gets the content type, so AutoFill works.
    func credentialContentType(_ contentType: CredentialContentType?) -> some View {
        textContentType(UITestEnvironment.isActive ? nil : contentType)
    }
}
