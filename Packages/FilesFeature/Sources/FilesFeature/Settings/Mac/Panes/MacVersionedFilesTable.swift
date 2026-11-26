#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let versionsWidth: CGFloat = 150
        static let stateWidth: CGFloat = 130
    }

    struct MacVersionedFilesTable: View {
        let store: StoreOf<VersionedFilesFeature>

        var body: some View {
            VStack(alignment: .leading, spacing: .zero) {
                MacTableHeader {
                    MacTableColumnTitle(L10n.VersionedFiles.pathHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MacTableColumnTitle(L10n.VersionedFiles.versionsHeader)
                        .frame(width: Metrics.versionsWidth, alignment: .leading)
                    MacTableColumnTitle(L10n.VersionedFiles.stateHeader)
                        .frame(width: Metrics.stateWidth, alignment: .leading)
                }
                if store.files.isEmpty, store.phase == .loaded {
                    Text(L10n.VersionedFiles.none)
                        .type(.body2(.regular), style: .secondary)
                        .padding(.horizontal, .space12)
                        .frame(height: MacTableMetrics.rowHeight)
                }
                ForEach(Array(store.files.enumerated()), id: \.element.id) { index, file in
                    MacVersionedFileRow(
                        file: file,
                        isShaded: index.isMultiple(of: 2),
                        isSelected: store.expanded.contains(file.id)
                    ) {
                        store.send(.fileToggled(file.id), animation: DSMotion.listDiff)
                    }
                }
            }
        }
    }

    private struct MacVersionedFileRow: View {
        let file: VersionedFile
        let isShaded: Bool
        let isSelected: Bool
        let onSelect: () -> Void

        var body: some View {
            MacTableRowButton(isShaded: isShaded, isSelected: isSelected, action: onSelect) {
                HStack(spacing: MacTableMetrics.columnSpacing) {
                    HStack(spacing: .space8) {
                        MacItemIcon(name: file.name, isDirectory: false)
                        Text(file.relativePath)
                            .type(.body2(.semibold))
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.VersionedFiles.rowSummary(file.versions, TrashSettingsView.bytes(file.bytes)))
                        .type(.body2(.regular))
                        .foregroundStyle(Color.macChromeSecondary)
                        .frame(width: Metrics.versionsWidth, alignment: .leading)
                    MacChip(text: VersionedFileWords.state(file.state), tone: VersionedFileWords.tone(file.state))
                        .frame(width: Metrics.stateWidth, alignment: .leading)
                }
            }
        }
    }

    extension VersionedFileWords {
        static func tone(_ state: VersionedFileState) -> MacChip.Tone {
            switch state {
            case .live: .green
            case .trashed: .amber
            case .orphaned: .gray
            }
        }
    }

    #Preview("Table") {
        var state = VersionedFilesFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.page = PreviewVersions.page
        state.phase = .loaded
        state.expanded = ["f1"]
        return MacVersionedFilesTable(store: Store(initialState: state) { EmptyReducer() })
            .padding(.space32)
            .previewCanvasWidth(.table)
            .background(Color.macCard)
    }

    #Preview("Table, empty") {
        var state = VersionedFilesFeature.State(serverURL: ServerSettingsPreview.serverURL)
        state.page = VersionedFilesPage()
        state.phase = .loaded
        return MacVersionedFilesTable(store: Store(initialState: state) { EmptyReducer() })
            .padding(.space32)
            .previewCanvasWidth(.table)
            .background(Color.macCard)
    }
#endif
