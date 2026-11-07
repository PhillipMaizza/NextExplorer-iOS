import Dependencies
import Foundation
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// What the sheet needs from the system's assistive technologies: whether one is driving the
/// screen (the sheet then stays longer before it closes) and a spoken announcement of the result.
public struct ShareAccessibilityClient: Sendable {
    public var isAssistiveTechnologyRunning: @Sendable () -> Bool
    public var announce: @Sendable (_ message: String) -> Void

    public init(
        isAssistiveTechnologyRunning: @escaping @Sendable () -> Bool,
        announce: @escaping @Sendable (_ message: String) -> Void
    ) {
        self.isAssistiveTechnologyRunning = isAssistiveTechnologyRunning
        self.announce = announce
    }
}

/// The accessibility flags belong to the main actor, and the reducer may ask from anywhere.
private func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(work)
    }
    return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
}

extension ShareAccessibilityClient: DependencyKey {
    public static var liveValue: ShareAccessibilityClient {
        #if os(iOS)
            ShareAccessibilityClient(
                isAssistiveTechnologyRunning: {
                    onMain { UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning }
                },
                announce: { message in
                    Task { @MainActor in UIAccessibility.post(notification: .announcement, argument: message) }
                }
            )
        #elseif os(macOS)
            ShareAccessibilityClient(
                isAssistiveTechnologyRunning: {
                    onMain { NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled }
                },
                announce: { message in
                    Task { @MainActor in
                        NSAccessibility.post(
                            element: NSApplication.shared,
                            notification: .announcementRequested,
                            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
                        )
                    }
                }
            )
        #endif
    }

    public static let testValue = ShareAccessibilityClient(isAssistiveTechnologyRunning: { false }, announce: { _ in })
    public static let previewValue = testValue
}

public extension DependencyValues {
    var shareAccessibility: ShareAccessibilityClient {
        get { self[ShareAccessibilityClient.self] }
        set { self[ShareAccessibilityClient.self] = newValue }
    }
}
