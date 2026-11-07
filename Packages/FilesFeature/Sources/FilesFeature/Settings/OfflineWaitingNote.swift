import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowSpacing: CGFloat = .space8
}

/// The note under the Download row while the pinned folders cannot be listed: it says why nothing is
/// moving, offers a Resync once something is pinned, and is announced to VoiceOver when it appears.
/// The caller shows it only while the offline state says it is waiting, so it goes away when the
/// state clears.
struct OfflineWaitingNote: View {
    /// `nil` where nothing is pinned yet, so there is nothing to resync.
    let onResync: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.rowSpacing) {
            Text(L10n.Offline.waitingForNetwork)
                .type(.body3(.regular), style: .secondary)
            Spacer(minLength: 0)
            if let onResync {
                Button(action: onResync) {
                    Text(L10n.Offline.resyncRow)
                        .type(.label4, style: .link)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            AccessibilityNotification.Announcement(L10n.Offline.waitingForNetwork).post()
        }
    }
}

#Preview("Waiting, with resync") {
    OfflineWaitingNote(onResync: {})
        .padding()
}

#Preview("Waiting, nothing pinned") {
    OfflineWaitingNote(onResync: nil)
        .padding()
}
