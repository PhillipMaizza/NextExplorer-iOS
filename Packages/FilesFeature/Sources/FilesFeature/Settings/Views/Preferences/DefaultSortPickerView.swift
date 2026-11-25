import AppStorageKeys
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconSmall
    static let checkmarkSize: CGFloat = .iconSmall
}

struct DefaultSortPickerView: View {
    @AppStorage(AppStorageKeys.defaultSortOption) private var option = BrowseFeature.SortOption.name
    @AppStorage(AppStorageKeys.defaultSortDirection) private var direction = BrowseFeature.SortDirection.ascending

    var body: some View {
        DSGroupedList {
            Section {
                ForEach(BrowseFeature.SortOption.allCases, id: \.self) { candidate in
                    row(title: candidate.title, icon: candidate.icon, isSelected: candidate == option) {
                        option = candidate
                    }
                }
            } header: {
                SettingsSectionHeader(L10n.Sort.sheetTitle)
            }
            .listRowBackground(Color.backgroundSecondary)

            Section {
                ForEach(BrowseFeature.SortDirection.allCases, id: \.self) { candidate in
                    row(title: candidate.title, icon: candidate.icon, isSelected: candidate == direction) {
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
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hapticFeedback(.selection, trigger: option)
            .hapticFeedback(.selection, trigger: direction)
    }

    private func row(title: String, icon: Image, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(title).type(.body1(.regular), style: .primaryOnSurface)
                } icon: {
                    icon
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: Constants.iconSize, height: Constants.iconSize)
                }
                Spacer()
                if isSelected {
                    IconKit.checkmark
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.accent)
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DSMotion.pop, value: isSelected)
    }
}

#Preview {
    NavigationStack {
        DefaultSortPickerView()
    }
}
