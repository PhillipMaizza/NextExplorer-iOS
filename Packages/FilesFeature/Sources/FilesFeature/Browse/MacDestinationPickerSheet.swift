#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 540
        static let height: CGFloat = 460
        static let padding: CGFloat = .space16
        static let searchWidth: CGFloat = 180
    }

    /// Move to and Upload to as a native Mac dialog: the folder being looked at with Back and a
    /// search field, its folders in a list (double click to open one), then Cancel and the
    /// confirm button for the folder on screen.
    struct MacDestinationPickerSheet: View {
        @Bindable var store: StoreOf<DestinationPickerFeature>
        let title: String
        let confirmTitle: String

        var body: some View {
            VStack(spacing: 0) {
                header
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Spacer()
                    Button(L10n.Common.cancel) { store.send(.cancelTapped) }
                        .keyboardShortcut(.cancelAction)
                    Button(confirmTitle) { store.send(.confirmTapped) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!store.canConfirm)
                }
                .padding(Metrics.padding)
            }
            .frame(width: Metrics.width, height: Metrics.height)
            .task { store.send(.onAppear) }
        }

        private var header: some View {
            HStack(spacing: .space8) {
                Button { store.send(.backTapped) } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.canNavigateBack)
                    .accessibilityLabel(L10n.Common.back)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.headline)
                    if !store.directoryPath.isEmpty {
                        Text(store.directoryPath)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer()
                TextField(L10n.Common.search, text: $store.searchQuery.sending(\.searchQueryChanged), prompt: Text(L10n.Common.search))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Metrics.searchWidth)
            }
            .padding(Metrics.padding)
        }

        @ViewBuilder
        private var content: some View {
            if !store.searchQuery.isEmpty {
                if store.isSearching, store.searchResults?.isEmpty ?? true {
                    ProgressView()
                } else if let results = store.searchResults, results.isEmpty {
                    ContentUnavailableView.search(text: store.searchQuery)
                } else {
                    List(store.searchResults ?? []) { result in
                        folderRow(result.name, subtitle: result.path.isEmpty ? nil : result.path)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { store.send(.searchResultTapped(result)) }
                    }
                }
            } else if store.phase == .loading, store.folders.isEmpty {
                ProgressView()
            } else if let errorMessage = store.phase.errorMessage {
                EmptyStateView(icon: IconKit.warning, message: errorMessage) { store.send(.retryTapped) }
            } else if store.folders.isEmpty {
                EmptyStateView(icon: IconKit.folder, message: L10n.Browse.destinationPickerNoFolders)
            } else {
                List(store.folders) { folder in
                    folderRow(folder.name, subtitle: nil)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { store.send(.folderTapped(folder)) }
                }
            }
        }

        private func folderRow(_ name: String, subtitle: String?) -> some View {
            Label {
                VStack(alignment: .leading) {
                    Text(name).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                }
            } icon: {
                Image(systemName: "folder.fill").foregroundStyle(Color.accent)
            }
        }
    }
#endif
