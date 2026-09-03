import DesignSystem
import SwiftUI

/// A neutral fill with a small spinner for a media thumbnail slot whose image or video frame
/// is still being produced. Picked file rows in the review sheet otherwise show blank squares
/// while a large photo decodes or `AVAssetImageGenerator` renders a video's first frame.
struct ThumbnailLoadingPlaceholder: View {
    var body: some View {
        ZStack {
            Color.backgroundSecondary
            DSSpinner(size: .small)
        }
    }
}

#Preview {
    ThumbnailLoadingPlaceholder()
        .frame(width: .iconLarge, height: .iconLarge)
        .clipShape(RoundedRectangle(cornerRadius: .radiusSmall))
}
