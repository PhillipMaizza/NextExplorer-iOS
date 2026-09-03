import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space24
    static let bottomPadding: CGFloat = .space24
    static let progressVerticalPadding: CGFloat = .space24
}

/// Shown the instant "Get Info" is tapped, while `GET /api/metadata/*` is still in flight —
/// a separate, deliberately tiny sheet rather than a loading branch inside `FileInfoSheet`
/// itself: iOS doesn't reliably honor a `presentationDetents` change on an already-presented
/// sheet (see `DSDynamicHeightSheet`), so growing one sheet from "spinner" to "full metadata"
/// gets stuck at the wrong height. Swapping to a *different* sheet identity once the fetch
/// resolves (`BrowseContentView.infoPhaseBinding`) gets a fresh presentation — and a fresh,
/// correctly-measured height — instead.
struct FileInfoLoadingSheet: View {
    let item: FileItem
    let onDismiss: () -> Void

    var body: some View {
        DSDynamicHeightSheet {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            DSSheetHeader(
                icon: item.isDirectory ? IconKit.folderFill : IconKit.document,
                title: item.name,
                closeAccessibilityLabel: L10n.Common.close,
                onClose: onDismiss
            )

            DSSpinner()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Constants.progressVerticalPadding)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FileInfoLoadingSheet(
                item: FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
                onDismiss: {}
            )
        }
}
