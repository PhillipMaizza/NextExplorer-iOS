import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconMedium
    static let chevronSize: CGFloat = .iconSmall
}

/// The modal folder chooser presented for "Move". Drills the same folder tree as Browse
/// (folders only) and hands the chosen path back to `BrowseFeature` on confirm. A grouped
/// list in a `NavigationStack`: close on the left of the bar, a checkmark on the right, and
/// the same breadcrumb bar Browse uses along the bottom.
struct DestinationPickerView: View {
    @Bindable var store: StoreOf<DestinationPickerFeature>

    private var navigationTitle: String {
        store.directoryPath.isEmpty
            ? L10n.Browse.destinationPickerMoveTitle
            : (store.directoryPath as NSString).lastPathComponent
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { store.send(.cancelTapped) } label: {
                            IconKit.close
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.primaryDS)
                                .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                        }
                        .accessibilityLabel(L10n.Common.close)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { store.send(.confirmTapped) } label: {
                            IconKit.checkmark
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.accent)
                                .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                        }
                        .disabled(!store.canConfirm)
                        .accessibilityLabel(L10n.Browse.destinationPickerConfirmMove)
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
        if store.isLoading && store.folders.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.errorMessage {
            EmptyStateView(icon: IconKit.warning, message: errorMessage) {
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
        if store.isSearching && (store.searchResults?.isEmpty ?? true) {
            ProgressView()
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
                    .type(.body2(.regular), style: .primary(for: .label))
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
