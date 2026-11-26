#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacFilesSettingsTab: View {
        let showHiddenFiles: Binding<Bool>?

        @AppStorage(AppStorageKeys.renderHTMLPages) private var shouldRenderHTMLPages = false
        @AppStorage(AppStorageKeys.renderMarkdownPages) private var shouldRenderMarkdownPages = false
        @AppStorage(AppStorageKeys.showFilenameExtensions) private var shouldShowFilenameExtensions = true
        @AppStorage(AppStorageKeys.defaultSortOption) private var defaultSortOption = BrowseFeature.SortOption.name
        @AppStorage(AppStorageKeys.defaultSortDirection) private var defaultSortDirection = BrowseFeature
            .SortDirection.ascending

        var body: some View {
            MacFormPage {
                MacFormGroup(L10n.Settings.groupFileLists) {
                    defaultSortRow
                    MacSwitchRow(L10n.Settings.toggleShowExtensions, isOn: $shouldShowFilenameExtensions)
                    if let showHiddenFiles {
                        MacSwitchRow(L10n.Settings.toggleShowHiddenFiles, isOn: showHiddenFiles)
                    }
                }
                MacFormGroup(L10n.Settings.groupPreviews) {
                    MacSwitchRow(L10n.Settings.toggleRenderMarkdown, isOn: $shouldRenderMarkdownPages)
                    MacSwitchRow(L10n.Settings.toggleRenderHTML, isOn: $shouldRenderHTMLPages)
                }
            }
        }

        private var defaultSortRow: some View {
            MacFormRow {
                MacRowTitle(title: L10n.Settings.rowDefaultSort, subtitle: L10n.Settings.defaultSortFooter)
            } control: {
                HStack(spacing: .space8) {
                    MacPopup(
                        L10n.Settings.rowDefaultSort,
                        valueLabel: defaultSortOption.title,
                        selection: $defaultSortOption
                    ) {
                        ForEach(BrowseFeature.SortOption.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    MacPopup(
                        L10n.Settings.rowSortOrder,
                        valueLabel: defaultSortDirection.title,
                        selection: $defaultSortDirection
                    ) {
                        ForEach(BrowseFeature.SortDirection.allCases, id: \.self) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                }
            }
        }
    }

    extension MacFilesSettingsTab {
        init(store: StoreOf<SettingsFeature>) {
            self.init(
                showHiddenFiles: Bindable(store).preferences.shouldShowHiddenFiles.sending(\.setShowHiddenFiles)
            )
        }
    }

    #Preview("Files") {
        MacFilesSettingsTab(store: Store(initialState: .macPreview) { SettingsFeature() })
            .previewCanvas(.settingsPane)
    }

    #Preview("Files, signed out") {
        MacFilesSettingsTab(showHiddenFiles: nil)
            .previewCanvas(.settingsPane)
    }
#endif
