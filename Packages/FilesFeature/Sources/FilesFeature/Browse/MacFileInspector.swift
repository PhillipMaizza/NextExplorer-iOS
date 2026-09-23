#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = .size44
        static let spacing: CGFloat = .space16
        static let minWidth: CGFloat = 260
        static let idealWidth: CGFloat = 300
        static let maxWidth: CGFloat = 420
    }

    /// Get Info on the Mac: a trailing inspector column instead of a sheet, so it can stay open
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
            .inspectorColumnWidth(min: Metrics.minWidth, ideal: Metrics.idealWidth, max: Metrics.maxWidth)
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

    /// One inspector per navigation stack, showing Get Info for whichever screen is on top.
    /// Attaching it per screen put several inspectors (and their toolbar items) in one window.
    struct MacBrowseInspector: ViewModifier {
        let screen: StoreOf<BrowseFeature>?

        func body(content: Content) -> some View {
            content.inspector(isPresented: Binding(
                get: { screen?.infoItem != nil },
                set: {
                    if !$0 {
                        screen?.send(.infoDismissed)
                    }
                }
            )) {
                if let screen, let item = screen.infoItem {
                    MacFileInspector(
                        item: item,
                        metadata: screen.infoMetadata,
                        usage: screen.infoUsage,
                        errorMessage: screen.infoErrorMessage,
                        onClose: { screen.send(.infoDismissed) }
                    )
                }
            }
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
