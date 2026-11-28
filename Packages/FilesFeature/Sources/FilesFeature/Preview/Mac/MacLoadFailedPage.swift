#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileSize: CGFloat = 112
        static let badgeSize: CGFloat = .size32
        static let badgeGlyphSize: CGFloat = .size16
        static let badgeOffset: CGFloat = .space8
    }

    struct MacPreviewDownload {
        let perform: () -> Void
    }

    extension EnvironmentValues {
        @Entry var macPreviewDownload: MacPreviewDownload?
    }

    struct MacLoadFailedPage: View {
        let item: FileItem
        let message: String
        let onRetry: () -> Void
        @Environment(\.macPreviewDownload) private var download

        var body: some View {
            VStack(spacing: .space12) {
                MacFileTile(item: item, size: Metrics.tileSize, shouldShowPlayBadge: false)
                    .overlay(alignment: .bottomTrailing) { badge }
                    .accessibilityHidden(true)
                Text(L10n.Gallery.loadFailedTitle(item.name))
                    .type(.body1(.semibold), style: .primaryOnSurface)
                    .multilineTextAlignment(.center)
                    .padding(.top, .space8)
                Text(message)
                    .type(.body2(.regular), style: .secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: .space12) {
                    Button(L10n.Common.retry, action: onRetry)
                        .buttonStyle(.macDS(.primary))
                    if let download {
                        Button(L10n.Common.download, action: download.perform)
                            .buttonStyle(.macDS(.secondary))
                    }
                }
                .padding(.top, .space8)
            }
            .padding(.space24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var badge: some View {
            Circle()
                .fill(Color.negative)
                .frame(width: Metrics.badgeSize, height: Metrics.badgeSize)
                .overlay {
                    IconKit.warning
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: Metrics.badgeGlyphSize, height: Metrics.badgeGlyphSize)
                }
                .offset(x: Metrics.badgeOffset, y: Metrics.badgeOffset)
        }
    }

    #Preview("Server error") {
        MacLoadFailedPage(
            item: FileItem(name: "vacation.jpg", path: "", dateModified: .distantPast, size: 2_400_000, kind: "jpg"),
            message: L10n.Gallery.checkConnection,
            onRetry: {}
        )
        .environment(\.macPreviewDownload, MacPreviewDownload {})
        .frame(width: 640, height: 440)
        .background(Color.macCard)
    }

    #Preview("Damaged, no download") {
        MacLoadFailedPage(
            item: FileItem(name: "scan.tiff", path: "", dateModified: .distantPast, size: 3_800_000, kind: "tiff"),
            message: L10n.Gallery.decodeFailed,
            onRetry: {}
        )
        .frame(width: 640, height: 440)
        .background(Color.macCard)
    }
#endif
