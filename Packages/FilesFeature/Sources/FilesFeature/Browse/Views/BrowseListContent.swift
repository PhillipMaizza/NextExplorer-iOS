import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// A folder or its search results as a grouped list.
struct BrowseListContent<Menu: View>: View {
    let store: StoreOf<BrowseFeature>
    let source: BrowsePreviewSource
    let keepsClipboard: Bool
    let bottomClearance: CGFloat
    let scrollTargetID: String?
    let onTap: (FileItem) -> Void
    @ViewBuilder let menu: (FileItem) -> Menu

    var body: some View {
        ScrollViewReader { proxy in
            DSGroupedList {
                if store.showsPersonalSpace {
                    Section {
                        PersonalSpaceRow { store.send(.personalSpaceTapped) }
                            .listRowBackground(Color.backgroundSecondary)
                    } header: {
                        BrowseRootSectionHeader(title: L10n.Browse.sectionPersonal)
                    }
                }
                if store.isSearching {
                    let sections = store.searchResultSections
                    if sections.isSplit {
                        Section {
                            BrowseSearchResultRows(store: store, results: sections.onDevice, source: source)
                        } header: {
                            BrowseRootSectionHeader(title: L10n.Search.onDevice)
                        }
                        if !sections.remote.isEmpty {
                            Section {
                                BrowseSearchResultRows(store: store, results: sections.remote, source: source)
                            } header: {
                                BrowseRootSectionHeader(title: L10n.Search.remote)
                            }
                        }
                    } else {
                        Section { BrowseSearchResultRows(store: store, results: sections.remote, source: source) }
                    }
                } else {
                    Section {
                        BrowseFolderRows(store: store, source: source, onTap: onTap, menu: menu)
                    } header: {
                        if store.showsPersonalSpace {
                            BrowseRootSectionHeader(title: L10n.Browse.locations)
                        }
                    }
                }
                if store.isSearching, BrowseSearchFooter.isShown(store) {
                    BrowseSearchFooter(store: store)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                BrowseOfflineFooter(dataSource: store.dataSource, isListRow: true)
                BrowsePasteTarget(store: store, keepsClipboard: keepsClipboard, isListRow: true)
            }
            .listStyle(.insetGrouped)
            .groupedListRowHover()
            .scrollContentBackground(.hidden)
            // Scrolling the results dismisses the search keyboard, the expected gesture when the
            // results fill the screen and tapping a row would navigate rather than just defocus.
            .scrollDismissesKeyboard(.immediately)
            .modifier(BrowseDragToSelect(store: store))
            .backgroundGradient()
            .safeAreaPadding(.bottom, bottomClearance)
            .scrollGalleryPageIntoView(proxy, id: scrollTargetID)
        }
    }
}

/// A folder or its search results as a grid of tiles: folders as roomy cards first, then the files
/// at the grid size the user picked. Folders always sort first, so the split keeps the sort order.
struct BrowseGridContent<Menu: View>: View {
    let store: StoreOf<BrowseFeature>
    let source: BrowsePreviewSource
    let keepsClipboard: Bool
    let bottomClearance: CGFloat
    let scrollTargetID: String?
    let onTap: (FileItem) -> Void
    @ViewBuilder let menu: (FileItem) -> Menu

    var body: some View {
        // Bind once: `store.displayedItems` filters + localized sorts on every read, and this
        // builder would otherwise hit it for the ForEach and the animation value separately.
        let displayedItems = store.displayedItems
        let groups = BrowseGridGroups(items: displayedItems)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: FileGridMetrics.sectionSpacing) {
                    if store.isSearching {
                        searchCells
                    } else {
                        if store.showsPersonalSpace {
                            section(L10n.Browse.sectionPersonal) {
                                FileGrid(.folders) {
                                    PersonalSpaceGridCell { store.send(.personalSpaceTapped) }
                                }
                            }
                        }
                        if !groups.folders.isEmpty {
                            section(store.showsPersonalSpace ? L10n.Browse.locations : L10n.Grid.sectionFolders) {
                                FileGrid(.folders) {
                                    cells(groups.folders)
                                }
                            }
                        }
                        if !groups.files.isEmpty {
                            section(L10n.Grid.sectionFiles) {
                                FileGrid {
                                    cells(groups.files)
                                }
                            }
                        }
                    }
                }
                .padding(FileGridMetrics.margin)
                .animation(
                    DSMotion.listDiff,
                    value: displayedItems
                )
                .animation(
                    DSMotion.listDiff,
                    value: store.displayedSearchResults
                )
                if store.isSearching, BrowseSearchFooter.isShown(store) {
                    BrowseSearchFooter(store: store)
                }
                BrowseOfflineFooter(dataSource: store.dataSource)
                BrowsePasteTarget(store: store, keepsClipboard: keepsClipboard)
            }
            .scrollDismissesKeyboard(.immediately)
            .modifier(BrowseDragToSelect(store: store))
            .backgroundGradient()
            .safeAreaPadding(.bottom, bottomClearance)
            .dismissKeyboardOnTap()
            .scrollGalleryPageIntoView(proxy, id: scrollTargetID)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: FileGridMetrics.headerSpacing) {
            BrowseRootSectionHeader(title: title)
            content()
        }
    }

    private func cells(_ items: IdentifiedArrayOf<FileItem>) -> some View {
        BrowseGridCells(store: store, items: items, source: source, onTap: onTap, menu: menu)
    }

    @ViewBuilder
    private var searchCells: some View {
        let sections = store.searchResultSections
        if sections.isSplit {
            section(L10n.Search.onDevice) {
                FileGrid {
                    BrowseSearchResultCells(store: store, results: sections.onDevice, source: source)
                }
            }
            if !sections.remote.isEmpty {
                section(L10n.Search.remote) {
                    FileGrid {
                        BrowseSearchResultCells(store: store, results: sections.remote, source: source)
                    }
                }
            }
        } else {
            FileGrid {
                BrowseSearchResultCells(store: store, results: sections.remote, source: source)
            }
        }
    }
}

/// A folder's items split for the grid: folder cards, then file tiles, each keeping its sort order.
struct BrowseGridGroups: Equatable {
    let folders: IdentifiedArrayOf<FileItem>
    let files: IdentifiedArrayOf<FileItem>

    init(items: IdentifiedArrayOf<FileItem>) {
        folders = items.filter(\.isDirectory)
        files = items.filter { !$0.isDirectory }
    }
}
