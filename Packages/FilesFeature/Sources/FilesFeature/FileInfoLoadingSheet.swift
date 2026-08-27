import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let headerIconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let contentSpacing: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space24
    static let bottomPadding: CGFloat = .space24
    static let progressVerticalPadding: CGFloat = .space24
}

/// Shown the instant "Get Info" is tapped, while `GET /api/metadata/*` is still in flight —
/// a separate, deliberately tiny sheet rather than a loading branch inside `FileInfoSheet`
/// itself: iOS doesn't reliably honor a `presentationDetents` change on an already-presented
/// sheet (see `DynamicHeightSheet`), so growing one sheet from "spinner" to "full metadata"
/// gets stuck at the wrong height. Swapping to a *different* sheet identity once the fetch
/// resolves (`BrowseContentView.infoPhaseBinding`) gets a fresh presentation — and a fresh,
/// correctly-measured height — instead.
struct FileInfoLoadingSheet: View {
    let item: FileItem
    let onDismiss: () -> Void

    var body: some View {
        DynamicHeightSheet {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            HStack {
                (item.isDirectory ? IconKit.folderFill : IconKit.document)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)

                Spacer()

                Button(action: onDismiss) {
                    IconKit.close
                        .resizable()
                        .foregroundStyle(Color.primaryDS)
                        .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                        .padding(Constants.closeButtonPadding)
                        .background(Circle().fill(Color.backgroundSecondary))
                }
                .buttonStyle(DSHapticButtonStyle())
            }

            Text(item.name).type(.headline3, style: .link).lineLimit(2)

            ProgressView()
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
