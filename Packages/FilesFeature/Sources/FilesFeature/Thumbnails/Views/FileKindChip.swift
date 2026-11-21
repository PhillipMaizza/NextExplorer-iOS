import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    /// The chip's side as a share of the well's shorter side.
    static let chipFraction: CGFloat = 0.35
    static let previewWidth: CGFloat = 110
}

/// A grid well for a file with nothing to show (an installer, a song with no artwork, a document
/// nothing could draw): its type icon in the shared symbol box, the extension beneath.
struct FileKindChip: View {
    let kind: String

    var body: some View {
        GridWellSymbol(kind: kind, shouldShowLabel: true) { wellSide in
            FileTypeIcon(kind: kind)
                .frame(width: wellSide * Constants.chipFraction, height: wellSide * Constants.chipFraction)
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private func previewRow() -> some View {
    HStack(spacing: .space12) {
        ForEach(["jar", "exe", "mp3", "pdf", ""], id: \.self) { kind in
            FileKindChip(kind: kind)
                .frame(width: Constants.previewWidth, height: Constants.previewWidth)
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous))
        }
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}

#Preview("Light") {
    previewRow()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    previewRow()
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    previewRow()
        .dynamicTypeSize(.accessibility2)
}
