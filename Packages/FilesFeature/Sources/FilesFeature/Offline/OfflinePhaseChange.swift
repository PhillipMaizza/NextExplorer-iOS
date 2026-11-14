import ComposableArchitecture
import FilesClient
import SwiftUI

extension View {
    /// Calls `action` with the offline run's phase when it changes, and once on appear when `initial`
    /// (a screen mirroring the phase in its own state needs the current one at once). The shared
    /// progress also carries bytes and the current file name, which change many times a second while
    /// files download; observing it in a list's own body rendered the whole list again on every tick and
    /// made scrolling stutter. Only this modifier observes it, so the screen updates per phase.
    func onOfflinePhaseChange(
        initial: Bool = false,
        _ action: @escaping (OfflineDownloadProgress.Phase) -> Void
    ) -> some View {
        modifier(OfflinePhaseChange(initial: initial, action: action))
    }
}

private struct OfflinePhaseChange: ViewModifier {
    let initial: Bool
    let action: (OfflineDownloadProgress.Phase) -> Void
    @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) private var progress = OfflineDownloadProgress()

    func body(content: Content) -> some View {
        content.onChange(of: progress.phase, initial: initial) { _, phase in action(phase) }
    }
}
