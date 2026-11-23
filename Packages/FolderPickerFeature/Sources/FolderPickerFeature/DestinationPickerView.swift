import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconMedium
    static let chevronSize: CGFloat = .iconSmall
    /// Uneven placeholder widths, so the redacted rows do not line up as one flat column.
    static let skeletonNames = [7, 12, 5, 10, 8, 14].map { String(repeating: "M", count: $0) }
}

/// The folder chooser for "Move" and "Upload": a modal sheet either way (for Upload it sits
/// over the review sheet). Drills the same folder tree as Browse (folders only), hands the
/// chosen path back on confirm. Grouped list, checkmark to confirm, the same breadcrumb bar
/// Browse uses.
public struct DestinationPickerView: View {
    @Bindable var store: StoreOf<DestinationPickerFeature>

    public init(store: StoreOf<DestinationPickerFeature>) {
        self.store = store
    }

    private var navigationTitle: String {
        store.directoryPath.isEmpty ? purposeTitle : (store.directoryPath as NSString).lastPathComponent
    }

    private var purposeTitle: String {
        switch store.purpose {
        case .upload: L10n.Uploads.destinationTitle
        case .move: L10n.Browse.destinationPickerMoveTitle
        case .copy: L10n.Browse.destinationPickerCopyTitle
        case .restore: L10n.Trash.restoreTo
        case .replaceFile: L10n.Browse.destinationPickerReplaceTitle
        }
    }

    private var confirmLabel: String {
        switch store.purpose {
        case .upload: L10n.Uploads.destinationConfirm
        case .move: L10n.Browse.destinationPickerConfirmMove
        case .copy: L10n.Browse.destinationPickerConfirmCopy
        case .restore: L10n.Trash.restoreHere
        case .replaceFile: L10n.Browse.transferConflictReplace
        }
    }

    public var body: some View {
        #if os(macOS)
            MacDestinationPickerSheet(store: store, title: purposeTitle, confirmTitle: confirmLabel)
        #else
            NavigationStack { pickerBody }
        #endif
    }

    private var pickerBody: some View {
        content
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.canNavigateBack {
                        Button { store.send(.backTapped) } label: {
                            IconKit.back
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.primaryDS)
                                .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                        }
                        .accessibilityLabel(L10n.Common.back)
                    } else {
                        Button { store.send(.cancelTapped) } label: {
                            IconKit.close
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.primaryDS)
                                .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                        }
                        .accessibilityLabel(L10n.Common.close)
                    }
                }
                if store.isRefiningSearch {
                    ToolbarItem(placement: .topBarTrailing) {
                        DSSpinner(size: .small)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.send(.confirmTapped) } label: {
                        IconKit.checkmark
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(store.canConfirm ? Color.accent : Color.tertiaryDS)
                            .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                    }
                    .disabled(!store.canConfirm)
                    .accessibilityLabel(confirmLabel)
                }
            }
            .searchable(
                text: $store.searchQuery.sending(\.searchQueryChanged),
                placement: .pinned,
                prompt: L10n.Common.search
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if store.isSearchTermTooShort {
                        Text(SearchHint.tooShort)
                            .type(.body3(.regular), style: .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, .space16)
                            .padding(.vertical, .space12)
                            .background(Color.backgroundPrimary)
                    }
                    if !store.directoryPath.isEmpty {
                        BrowseBreadcrumbBar(directoryPath: store.directoryPath) { path, _ in
                            store.send(.breadcrumbTapped(path: path))
                        }
                    }
                }
            }
            .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        if store.showsSearchResults {
            searchContent
        } else {
            browseContent
        }
    }

    @ViewBuilder
    private var browseContent: some View {
        if store.phase == .loading, store.folders.isEmpty {
            DSSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.phase.errorMessage {
            EmptyStateView(
                icon: IconKit.warning,
                message: errorMessage
            ) {
                store.send(.retryTapped)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.folders.isEmpty, !store.showsRecentsSection {
            EmptyStateView(icon: IconKit.folder, message: L10n.Browse.destinationPickerNoFolders)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.displayedFolders.isEmpty, !store.showsRecentsSection {
            EmptyStateView(icon: IconKit.search, message: L10n.EmptyState.noSearchMatches(store.searchQuery))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DSGroupedList {
                if store.showsRecentsSection {
                    Section(L10n.Browse.destinationPickerRecent) {
                        ForEach(store.displayedRecents, id: \.self) { path in
                            Button {
                                store.send(.recentTapped(path))
                            } label: {
                                folderRow((path as NSString).lastPathComponent, subtitle: path, icon: IconKit.time)
                            }
                        }
                    }
                }
                Section {
                    ForEach(store.displayedFolders) { folder in
                        Button {
                            store.send(.folderTapped(folder))
                        } label: {
                            folderRow(
                                PersonalSpace.displayName(forSegment: folder.name, isFirstSegment: folder.path.isEmpty),
                                subtitle: nil
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if store.searchPhase == .loading, store.searchResults.isEmpty {
            // Placeholder folder rows for the answer to come, not a second spinner.
            DSGroupedList {
                ForEach(Array(Constants.skeletonNames.enumerated()), id: \.offset) { _, name in
                    folderRow(name, subtitle: name)
                        .redacted(reason: .placeholder)
                        .shimmering()
                }
            }
            .listStyle(.insetGrouped)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if let errorMessage = store.searchPhase.errorMessage {
            EmptyStateView(icon: IconKit.warning, message: errorMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.searchResults.isEmpty {
            EmptyStateView(icon: IconKit.search, message: L10n.EmptyState.noSearchMatches(store.searchQuery))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DSGroupedList {
                ForEach(store.searchResults) { result in
                    Button {
                        store.send(.searchResultTapped(result))
                    } label: {
                        folderRow(result.name, subtitle: result.path.isEmpty ? nil : result.path)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func folderRow(_ name: String, subtitle: String?, icon: Image = IconKit.folder) -> some View {
        HStack(spacing: .space12) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            VStack(alignment: .leading, spacing: .space2) {
                Text(name)
                    .type(.body2(.regular), style: .primaryOnSurface)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            IconKit.chevronRight
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.chevronSize, height: Constants.chevronSize)
        }
        .contentShape(Rectangle())
    }
}

#Preview("Short term filters by name") {
    var state = DestinationPickerFeature.State(
        serverURL: URL(string: "https://example.com")!,
        items: [FileItem(name: "report.pdf", path: "Documents", dateModified: .now, size: 0, kind: "pdf")]
    )
    state.searchQuery = "P"
    return DestinationPickerView(
        store: Store(initialState: state) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}

#Preview("Refining a search") {
    var state = DestinationPickerFeature.State(
        serverURL: URL(string: "https://example.com")!,
        items: [FileItem(name: "report.pdf", path: "Documents", dateModified: .now, size: 0, kind: "pdf")]
    )
    state.searchQuery = "Pho"
    state.searchPhase = .loading
    state.searchResults = [SearchResultItem(name: "Photos", path: "Media", kind: "dir")]
    return DestinationPickerView(store: Store(initialState: state) { EmptyReducer() })
}

#Preview("Searching") {
    var state = DestinationPickerFeature.State(
        serverURL: URL(string: "https://example.com")!,
        items: [FileItem(name: "report.pdf", path: "Documents", dateModified: .now, size: 0, kind: "pdf")]
    )
    state.searchQuery = "Pho"
    state.searchPhase = .loading
    return DestinationPickerView(store: Store(initialState: state) { EmptyReducer() })
}

#Preview("Search failed") {
    var state = DestinationPickerFeature.State(
        serverURL: URL(string: "https://example.com")!,
        items: [FileItem(name: "report.pdf", path: "Documents", dateModified: .now, size: 0, kind: "pdf")]
    )
    state.searchQuery = "Pho"
    state.searchPhase = .failed(L10n.Browse.searchFailed)
    return DestinationPickerView(store: Store(initialState: state) { EmptyReducer() })
}

#Preview("Recent destinations") {
    var state = DestinationPickerFeature.State(
        serverURL: URL(string: "https://example.com")!,
        items: [FileItem(name: "report.pdf", path: "Documents", dateModified: .now, size: 0, kind: "pdf")]
    )
    state.recents = ["Documents/Projects", "Media/Photos"]
    return DestinationPickerView(
        store: Store(initialState: state) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}

#Preview("Folders") {
    DestinationPickerView(
        store: Store(
            initialState: DestinationPickerFeature.State(
                serverURL: URL(string: "https://example.com")!,
                items: [FileItem(name: "report.pdf", path: "Documents", dateModified: .now, size: 0, kind: "pdf")]
            )
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}
