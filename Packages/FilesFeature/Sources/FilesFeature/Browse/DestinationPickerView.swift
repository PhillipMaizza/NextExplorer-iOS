import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconMedium
    static let chevronSize: CGFloat = .iconSmall
}

/// The folder chooser for "Move" and "Upload" — a modal sheet either way (for Upload it sits
/// over the review sheet). Drills the same folder tree as Browse (folders only), hands the
/// chosen path back on confirm. Grouped list, checkmark to confirm, the same breadcrumb bar
/// Browse uses.
struct DestinationPickerView: View {
    @Bindable var store: StoreOf<DestinationPickerFeature>

    private var navigationTitle: String {
        guard store.directoryPath.isEmpty else {
            return (store.directoryPath as NSString).lastPathComponent
        }
        return store.purpose == .upload
            ? L10n.Uploads.destinationTitle
            : L10n.Browse.destinationPickerMoveTitle
    }

    private var confirmLabel: String {
        store.purpose == .upload
            ? L10n.Uploads.destinationConfirm
            : L10n.Browse.destinationPickerConfirmMove
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
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.Common.search
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !store.directoryPath.isEmpty {
                    BrowseBreadcrumbBar(directoryPath: store.directoryPath) { path, _ in
                        store.send(.breadcrumbTapped(path: path))
                    }
                }
            }
            .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        if !store.searchQuery.isEmpty {
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
        } else if store.folders.isEmpty {
            EmptyStateView(icon: IconKit.folder, message: L10n.Browse.destinationPickerNoFolders)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.folders) { folder in
                    Button {
                        store.send(.folderTapped(folder))
                    } label: {
                        folderRow(folder.name, subtitle: nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if store.isSearching, store.searchResults?.isEmpty ?? true {
            DSSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let results = store.searchResults, results.isEmpty {
            EmptyStateView(icon: IconKit.search, message: L10n.EmptyState.noSearchMatches(store.searchQuery))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.searchResults ?? []) { result in
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

    private func folderRow(_ name: String, subtitle: String?) -> some View {
        HStack(spacing: .space12) {
            IconKit.folder
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
