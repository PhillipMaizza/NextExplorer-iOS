import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// Size + save-location subtitle for a local download. The `ByteCountFormatter` is shared across
/// the list row and grid cell, so its holder is `@MainActor` (a bare module-level static is not
/// concurrency-safe, rule #10 §17).
@MainActor
enum DownloadFormatting {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func subtitle(for download: LocalDownload) -> String {
        "\(byteFormatter.string(fromByteCount: download.size)) • \(download.location.title)"
    }
}

/// One local download in the Downloads list, built on the shared `SelectableListRow` shell. Tap
/// toggles selection while selecting, otherwise hands back through `onPreview` so the host drives
/// the `.zoom` cover; delete / rename / share hang off the trailing swipe and the shared menu.
struct DownloadListRow: View {
    let store: StoreOf<DownloadsFeature>
    let download: LocalDownload
    let namespace: Namespace.ID
    let openURL: OpenURLAction
    let isFirst: Bool
    let isLast: Bool
    let onPreview: () -> Void

    var body: some View {
        SelectableListRow(
            isSelecting: store.isSelecting,
            isSelected: store.selectedDownloadIDs.contains(download.id),
            isFirst: isFirst,
            isLast: isLast,
            onTap: handleTap
        ) {
            FileRowView(
                name: download.fileName,
                isDirectory: false,
                subtitle: DownloadFormatting.subtitle(for: download),
                kind: (download.fileName as NSString).pathExtension,
                matchedSource: PreviewMatchedSource(id: download.id, namespace: namespace)
            )
        } trailingSwipe: {
            if !store.isSelecting {
                // No `role: .destructive` — a destructive-role swipe button makes `List`
                // collapse the row itself the moment it's tapped, before the confirmation
                // alert is answered. On Cancel the row is already gone, and the next data
                // update crashes the collection view with a section-count mismatch.
                Button {
                    store.send(.deleteTapped(download))
                } label: {
                    IconKit.delete
                }
                .tint(.negative)
                .accessibilityLabel(L10n.Common.delete)
                Button {
                    store.send(.renameTapped(download))
                } label: {
                    IconKit.rename
                }
                .tint(.positive)
                .accessibilityLabel(L10n.Browse.actionRename)
                // The plain system share sheet — local downloads have no server-side
                // sharing semantics to worry about, unlike Browse's items.
                ShareLink(item: download.url) {
                    IconKit.share
                }
                .tint(.accent)
                .accessibilityLabel(L10n.Common.share)
            }
        } contextMenu: {
            if !store.isSelecting {
                DownloadRowContextMenu(store: store, download: download, openURL: openURL)
            }
        }
    }

    private func handleTap() {
        if store.isSelecting {
            store.send(.itemSelectionToggled(download.id))
        } else {
            onPreview()
        }
    }
}

/// One local download as a grid tile: the same behavior as `DownloadListRow` on the shared
/// `SelectableGridCell` shell.
struct DownloadGridCell: View {
    let store: StoreOf<DownloadsFeature>
    let download: LocalDownload
    let namespace: Namespace.ID
    let openURL: OpenURLAction
    let onPreview: () -> Void

    var body: some View {
        SelectableGridCell(
            isSelecting: store.isSelecting,
            isSelected: store.selectedDownloadIDs.contains(download.id),
            onTap: handleTap
        ) {
            GridCellView(
                name: download.fileName,
                isDirectory: false,
                kind: (download.fileName as NSString).pathExtension,
                matchedSource: PreviewMatchedSource(id: download.id, namespace: namespace)
            )
        } contextMenu: {
            if !store.isSelecting {
                DownloadRowContextMenu(store: store, download: download, openURL: openURL)
            }
        }
    }

    private func handleTap() {
        if store.isSelecting {
            store.send(.itemSelectionToggled(download.id))
        } else {
            onPreview()
        }
    }
}

private extension LocalDownload {
    static var preview: LocalDownload {
        LocalDownload(
            url: URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf"),
            fileName: "report.pdf",
            location: .documents,
            size: 245_000,
            modifiedDate: Date()
        )
    }
}

#Preview("List row") {
    let store = Store(initialState: DownloadsFeature.State()) { DownloadsFeature() }
    return DownloadRowPreview { namespace in
        DSGroupedList {
            DownloadListRow(store: store, download: .preview, namespace: namespace, openURL: OpenURLAction { _ in .handled }, isFirst: true, isLast: true, onPreview: {})
        }
        .listStyle(.insetGrouped)
    }
}

#Preview("Grid cell") {
    let store = Store(initialState: DownloadsFeature.State()) { DownloadsFeature() }
    return DownloadRowPreview { namespace in
        DownloadGridCell(store: store, download: .preview, namespace: namespace, openURL: OpenURLAction { _ in .handled }, onPreview: {})
            .frame(width: 120)
            .padding()
    }
}

/// Supplies a `Namespace.ID` to a preview body (a `@Namespace` can't be declared at file scope).
private struct DownloadRowPreview<Content: View>: View {
    @Namespace private var namespace
    @ViewBuilder let content: (Namespace.ID) -> Content
    var body: some View {
        content(namespace)
    }
}
