import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconMedium
    static let chevronSize: CGFloat = .iconSmall
    static let selectionSize: CGFloat = .iconMedium

    @MainActor static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}

/// Multi select browser for choosing what to keep available offline. Drills the same tree as
/// Browse, shows files and folders, and sums a running size estimate for the current selection.
/// Confirming hands the chosen roots back to Settings.
struct OfflineSelectionView: View {
    @Bindable var store: StoreOf<OfflineSelectionFeature>

    private var navigationTitle: String {
        store.directoryPath.isEmpty
            ? L10n.Offline.selectionTitle
            : (store.directoryPath as NSString).lastPathComponent
    }

    var body: some View {
        NavigationStack { pickerBody }
    }

    private var pickerBody: some View {
        content
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.canNavigateBack {
                        toolbarButton(icon: IconKit.back, label: L10n.Common.back) { store.send(.backTapped) }
                    } else {
                        toolbarButton(icon: IconKit.close, label: L10n.Common.close) { store.send(.cancelTapped) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !store.directoryPath.isEmpty {
                        BrowseBreadcrumbBar(directoryPath: store.directoryPath) { path, _ in
                            store.send(.breadcrumbTapped(path: path))
                        }
                    }
                    selectionFooter
                }
            }
            .task { store.send(.onAppear) }
    }

    private func toolbarButton(icon: Image, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.primaryDS)
                .frame(width: Constants.chevronSize, height: Constants.chevronSize)
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var content: some View {
        if store.phase == .loading, store.items.isEmpty {
            DSSpinner().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.phase.errorMessage {
            EmptyStateView(icon: IconKit.warning, message: errorMessage) { store.send(.retryTapped) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty {
            EmptyStateView(icon: IconKit.folder, message: L10n.Offline.selectionEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.items) { item in
                    OfflineSelectionRow(
                        item: item,
                        isSelected: store.selection[item.id] != nil,
                        isAlreadyOffline: store.alreadyOfflineIDs.contains(item.id),
                        onToggle: { store.send(.selectionToggled(item)) },
                        onDrill: item.isDirectory ? { store.send(.folderTapped(item)) } : { store.send(.selectionToggled(item)) }
                    )
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Free space the OS considers available for important on-device storage. `nil` (unknown) is
    /// treated as unlimited so the guard never blocks a download it can't size.
    private var deviceFreeBytes: Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    private var exceedsFreeSpace: Bool {
        !store.isEstimating && store.estimatedBytes > deviceFreeBytes
    }

    private var selectionFooter: some View {
        DSSheetFooter {
            VStack(spacing: .space12) {
                HStack {
                    Text(L10n.Offline.selectionEstimate)
                        .type(.body3(.regular), style: .secondary)
                    Spacer()
                    Text(estimateText)
                        .type(.label3, style: .primaryOnSurface)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                if exceedsFreeSpace {
                    Text(L10n.Offline.selectionInsufficientSpace)
                        .type(.body3(.regular), style: .error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DSButton(
                    L10n.Offline.selectionDownload,
                    action: { store.send(.confirmTapped) }
                )
                .disabled(!store.canConfirm || exceedsFreeSpace)
            }
        }
    }

    private var estimateText: String {
        let size = Constants.byteFormatter.string(fromByteCount: store.estimatedBytes)
        return store.isEstimating ? "\(size)…" : size
    }
}

/// One row in the offline chooser: a selection glyph, an icon, the name (with a size for files), and
/// a drill chevron for folders. Tapping the glyph toggles selection; tapping the row body drills into
/// a folder or toggles a file.
private struct OfflineSelectionRow: View {
    let item: FileItem
    let isSelected: Bool
    /// Already downloaded for offline use: shown pre checked, dimmed to 50%, and not tappable.
    var isAlreadyOffline: Bool = false
    let onToggle: () -> Void
    let onDrill: () -> Void

    private static let byteFormatter = Constants.byteFormatter
    private static let alreadyOfflineOpacity: Double = 0.5

    var body: some View {
        HStack(spacing: .space12) {
            Button(action: onToggle) {
                DSSelectionIndicator(isSelected: isSelected || isAlreadyOffline, size: Constants.selectionSize)
            }
            .buttonStyle(.plain)
            .disabled(isAlreadyOffline)
            .accessibilityLabel(isSelected ? L10n.Common.deselect : L10n.Common.select)

            Button(action: onDrill) {
                rowContent
            }
            .buttonStyle(.plain)
            // A pinned file can't be re selected, but a folder is still drillable to reach files
            // deeper in it, so only files are made non tappable here.
            .disabled(isAlreadyOffline && !item.isDirectory)
        }
        .opacity(isAlreadyOffline ? Self.alreadyOfflineOpacity : 1)
        .contentShape(Rectangle())
    }

    private var rowContent: some View {
        HStack(spacing: .space12) {
            (item.isDirectory ? IconKit.folder : IconKit.document)
                .resizable()
                .scaledToFit()
                .foregroundStyle(item.isDirectory ? Color.accent : Color.secondaryDS)
                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            VStack(alignment: .leading, spacing: .space2) {
                Text(item.name)
                    .type(.body2(.regular), style: .primaryOnSurface)
                    .lineLimit(1)
                if !item.isDirectory {
                    Text(Self.byteFormatter.string(fromByteCount: item.size))
                        .type(.body3(.regular), style: .secondary)
                }
            }
            Spacer()
            if item.isDirectory {
                IconKit.chevronRight
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.chevronSize, height: Constants.chevronSize)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview("Selection") {
    OfflineSelectionView(
        store: Store(
            initialState: OfflineSelectionFeature.State(
                serverURL: URL(string: "https://example.com")!
            )
        ) {
            OfflineSelectionFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}
