import DesignSystem
import Localization
import SwiftUI

/// The space the Offline tab's items take on this device, pinned items and files saved earlier together.
struct OfflineStorageSummary: View {
    let bytes: Int64

    var body: some View {
        Text(L10n.Offline.available(FileSizeFormat.string(bytes)))
            .type(.body3(.regular), style: .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, .space8)
            .background(.bar)
    }
}

#Preview("Summary") {
    OfflineStorageSummary(bytes: 48_200_000)
}
