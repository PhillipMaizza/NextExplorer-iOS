import SwiftUI

/// The Available Offline button of a preview's action bar: what it shows for the file on screen and
/// what a tap does. `isEnabled` is false when the file is offline only because a parent folder is.
struct PreviewOfflineAction: Sendable {
    let isOn: Bool
    let isEnabled: Bool
    let toggle: @MainActor () -> Void
}

private struct PreviewOfflineKey: EnvironmentKey {
    static let defaultValue: PreviewOfflineAction? = nil
}

extension EnvironmentValues {
    var previewOffline: PreviewOfflineAction? {
        get { self[PreviewOfflineKey.self] }
        set { self[PreviewOfflineKey.self] = newValue }
    }
}
