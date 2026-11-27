#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let dash: [CGFloat] = [6, 4]
        static let dashOpacity: Double = .opacityWash
    }

    struct MacBrowseDropZone: View {
        let canCreateFolder: Bool
        let onCreateFolder: () -> Void
        let onUpload: () -> Void

        var body: some View {
            VStack(spacing: .space12) {
                EmptyGuideTile(icon: IconKit.macUpload, size: .size64)
                Text(L10n.EmptyGuide.browseDropTitle)
                    .type(.headline2)
                    .foregroundStyle(Color.primaryDS)
                    .padding(.top, .space4)
                Text(L10n.EmptyState.folderEmpty)
                    .type(.body1(.regular), style: .secondary)
                HStack(spacing: .space8) {
                    if canCreateFolder {
                        Button(action: onCreateFolder) {
                            Label { Text(L10n.Browse.actionNewFolder) } icon: { MenuIcon.newFolder.image }
                        }
                    }
                    Button(action: onUpload) {
                        Label { Text(L10n.Uploads.actionUploadFromFiles) } icon: { MenuIcon.upload.image }
                    }
                }
                .buttonStyle(.macDS(.secondary))
                .padding(.top, .space8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, .size96)
            .padding(.vertical, .size56)
            .overlay {
                RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous)
                    .strokeBorder(
                        Color.primaryDS.opacity(Metrics.dashOpacity),
                        style: StrokeStyle(lineWidth: .borderWidthFocused, dash: Metrics.dash)
                    )
            }
            .padding(.space40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    #Preview("Drop zone") {
        MacBrowseDropZone(canCreateFolder: true, onCreateFolder: {}, onUpload: {})
            .frame(width: 860, height: 520)
            .background(Color.macCard)
    }

    #Preview("Drop zone, upload only, light") {
        MacBrowseDropZone(canCreateFolder: false, onCreateFolder: {}, onUpload: {})
            .frame(width: 600, height: 480)
            .background(Color.macCard)
            .preferredColorScheme(.light)
    }
#endif
