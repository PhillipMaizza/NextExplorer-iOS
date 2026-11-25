import AppStorageKeys
import DesignSystem
import Localization
import SwiftUI

struct DefaultSortPickerView: View {
    @AppStorage(AppStorageKeys.defaultSortOption) private var option = BrowseFeature.SortOption.name
    @AppStorage(AppStorageKeys.defaultSortDirection) private var direction = BrowseFeature.SortDirection.ascending

    var body: some View {
        DSGroupedList {
            Section {
                ForEach(BrowseFeature.SortOption.allCases, id: \.self) { candidate in
                    SettingsCheckRow(title: candidate.title, icon: candidate.icon, isSelected: candidate == option) {
                        option = candidate
                    }
                }
            } header: {
                SettingsSectionHeader(L10n.Sort.sheetTitle)
            }
            .listRowBackground(Color.backgroundSecondary)

            Section {
                ForEach(BrowseFeature.SortDirection.allCases, id: \.self) { candidate in
                    SettingsCheckRow(title: candidate.title, icon: candidate.icon, isSelected: candidate == direction) {
                        direction = candidate
                    }
                }
            } header: {
                SettingsSectionHeader(L10n.Settings.rowSortOrder)
            } footer: {
                Text(L10n.Settings.defaultSortFooter)
                    .type(.body3(.regular), style: .tertiary)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .navigationTitle(L10n.Settings.rowDefaultSort)
        .navigationBarTitleDisplayMode(.inline)
        .hapticFeedback(.selection, trigger: option)
        .hapticFeedback(.selection, trigger: direction)
    }
}

#Preview {
    NavigationStack {
        DefaultSortPickerView()
    }
}
