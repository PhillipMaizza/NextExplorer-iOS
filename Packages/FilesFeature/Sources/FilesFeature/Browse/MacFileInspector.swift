#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = .size44
        static let spacing: CGFloat = .space16
        static let width: CGFloat = 300
        static let slideDuration: Double = 0.2
    }

    /// Get Info on the Mac: a trailing side panel instead of a sheet, so it can stay open
    /// while the selection moves (`BrowseFeature` reloads it for each newly selected row).
    struct MacFileInspector: View {
        let item: FileItem
        let metadata: FileMetadata?
        let usage: StorageUsage?
        let errorMessage: String?
        let onClose: () -> Void

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.spacing) {
                    header
                    if let errorMessage {
                        DSErrorCard(errorMessage)
                    } else if let metadata {
                        FileInfoDetails(metadata: metadata, usage: usage, stacksValues: true)
                    } else {
                        DSSpinner()
                            .frame(maxWidth: .infinity)
                            .padding(.top, .space24)
                    }
                }
                .padding(Metrics.spacing)
            }
            .frame(width: Metrics.width)
            // Kept inside the safe area so the panel starts below the toolbar, not under it.
            .background(Color.backgroundSecondary, ignoresSafeAreaEdges: [])
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: .space8) {
                // Close lives in the panel, not the window toolbar, so the inspector never adds
                // toolbar items of its own.
                HStack {
                    Spacer()
                    Button(action: onClose) { IconKit.close }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.secondaryDS)
                        .accessibilityLabelWithTooltip(L10n.Common.close)
                        .keyboardShortcut(.cancelAction)
                }
                if item.isDirectory {
                    IconKit.folderFill
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.accent)
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                } else {
                    FileTypeIcon(kind: item.kind)
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                }
                Text(item.name)
                    .type(.headline3, style: .primaryOnSurface)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    /// Get Info beside a Browse screen, as a plain side panel on each screen rather than
    /// SwiftUI's `.inspector` around the stack: wrapped around a `NavigationStack`, that stopped
    /// showing pushes past the third folder deep.
    struct MacBrowseInspector: ViewModifier {
        let screen: StoreOf<BrowseFeature>

        func body(content: Content) -> some View {
            HStack(spacing: 0) {
                content
                if let item = screen.infoItem {
                    Divider()
                    MacFileInspector(
                        item: item,
                        metadata: screen.infoMetadata,
                        usage: screen.infoUsage,
                        errorMessage: screen.infoErrorMessage,
                        onClose: { screen.send(.infoDismissed) }
                    )
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: Metrics.slideDuration), value: screen.infoItem == nil)
        }
    }

    #Preview("Loading") {
        MacFileInspector(
            item: FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 2_400_000, kind: "pdf"),
            metadata: nil, usage: nil, errorMessage: nil, onClose: {}
        )
    }

    #Preview("Loaded") {
        MacFileInspector(
            item: FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 2_400_000, kind: "pdf"),
            metadata: FileMetadata(
                path: "Docs/report.pdf", name: "report.pdf", kind: "pdf", size: 2_400_000,
                dateModified: Date(), dateCreated: Date().addingTimeInterval(-86_400)
            ),
            usage: nil, errorMessage: nil, onClose: {}
        )
    }

    #Preview("Error") {
        MacFileInspector(
            item: FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
            metadata: nil, usage: nil, errorMessage: "Couldn't reach the server.", onClose: {}
        )
    }
#endif
