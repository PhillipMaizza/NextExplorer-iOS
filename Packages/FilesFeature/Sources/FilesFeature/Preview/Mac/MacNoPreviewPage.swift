#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import QuickLookThumbnailing
    import SwiftUI

    private enum Metrics {
        static let tileSize: CGFloat = 112
        static let probeSize: CGFloat = .size40
    }

    enum QuickLookSupport {
        static func rendersContent(of url: URL) async -> Bool {
            let size = await Task.detached(priority: .userInitiated) {
                (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .zero
            }.value
            guard size > .zero else { return false }
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: Metrics.probeSize, height: Metrics.probeSize),
                scale: 1,
                representationTypes: .all
            )
            guard let best = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
                return false
            }
            return best.type != .icon
        }
    }

    struct MacNoPreviewPage: View {
        let item: FileItem
        let source: SystemShareSource
        @Environment(\.canExportPreview) private var canExport

        var body: some View {
            VStack(spacing: .space12) {
                MacFileTile(item: item, size: Metrics.tileSize, shouldShowPlayBadge: false)
                    .accessibilityHidden(true)
                Text(L10n.UnsupportedPreview.noPreview(item.previewTypeText))
                    .type(.body2(.regular), style: .secondary)
                    .multilineTextAlignment(.center)
                MacOpenWithSplitButton(source: canExport ? source : .unavailable)
                    .padding(.top, .space8)
            }
            .padding(.space24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.macCard.ignoresSafeArea())
        }
    }

    #Preview("No preview") {
        MacNoPreviewPage(
            item: FileItem(name: "deck.pptx", path: "", dateModified: .distantPast, size: 2_048, kind: "pptx"),
            source: .local(URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist"))
        )
        .frame(width: 600, height: 400)
    }

    #Preview("No apps") {
        MacNoPreviewPage(
            item: FileItem(name: "test.dat", path: "", dateModified: .distantPast, size: 6_144, kind: "dat"),
            source: .unavailable
        )
        .frame(width: 600, height: 400)
    }
#endif
