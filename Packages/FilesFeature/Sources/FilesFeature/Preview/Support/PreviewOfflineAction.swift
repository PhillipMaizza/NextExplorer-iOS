import SwiftUI

/// The Available Offline button of a preview's action bar: what it shows for the file on screen and
/// what a tap does.
struct PreviewOfflineAction: Sendable {
    let isOn: Bool
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

private struct PreviewCanExportKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var canExportPreview: Bool {
        get { self[PreviewCanExportKey.self] }
        set { self[PreviewCanExportKey.self] = newValue }
    }
}
