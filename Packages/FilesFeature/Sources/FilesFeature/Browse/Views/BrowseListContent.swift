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
                if store.showsTrashRow {
                    Section {
                        TrashRootRow { store.send(.trashTapped) }
                            .listRowBackground(Color.backgroundSecondary)
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

/// A folder or its search results as a grid of tiles.
struct BrowseGridContent<Menu: View>: View {
    let store: StoreOf<BrowseFeature>
    let source: BrowsePreviewSource
    let iconSize: CGFloat
    let keepsClipboard: Bool
    let bottomClearance: CGFloat
    let scrollTargetID: String?
    let onTap: (FileItem) -> Void
    @ViewBuilder let menu: (FileItem) -> Menu

    var body: some View {
        // Bind once: `store.displayedItems` filters + localized sorts on every read, and this
        // builder would otherwise hit it for the ForEach and the animation value separately.
        let displayedItems = store.displayedItems
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: FileGridMetrics.columns, spacing: FileGridMetrics.spacing) {
                    if store.isSearching {
                        searchCells
                    } else {
                        if store.showsPersonalSpace {
                            Section {
                                PersonalSpaceGridCell(
                                    iconSize: iconSize,
                                    cellPadding: FileGridMetrics.cellPadding
                                ) {
                                    store.send(.personalSpaceTapped)
                                }
                            } header: {
                                BrowseRootSectionHeader(title: L10n.Browse.sectionPersonal)
                            }
                        }
                        Section {
                            BrowseGridCells(
                                store: store,
                                items: displayedItems,
                                source: source,
                                iconSize: iconSize,
                                onTap: onTap,
                                menu: menu
                            )
                        } header: {
                            if store.showsPersonalSpace {
                                BrowseRootSectionHeader(title: L10n.Browse.locations)
                            }
                        }
                        if store.showsTrashRow {
                            TrashRootGridCell(iconSize: iconSize, cellPadding: FileGridMetrics.cellPadding) {
                                store.send(.trashTapped)
                            }
                        }
                    }
                }
                .padding(FileGridMetrics.spacing)
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

    @ViewBuilder
    private var searchCells: some View {
        let sections = store.searchResultSections
        if sections.isSplit {
            Section {
                BrowseSearchResultCells(store: store, results: sections.onDevice, source: source, iconSize: iconSize)
            } header: {
                BrowseRootSectionHeader(title: L10n.Search.onDevice)
            }
            if !sections.remote.isEmpty {
                Section {
                    BrowseSearchResultCells(store: store, results: sections.remote, source: source, iconSize: iconSize)
                } header: {
                    BrowseRootSectionHeader(title: L10n.Search.remote)
                }
            }
        } else {
            BrowseSearchResultCells(store: store, results: sections.remote, source: source, iconSize: iconSize)
        }
    }
}
