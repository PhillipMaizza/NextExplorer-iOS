import AppStorageKeys
import DesignSystem
import Localization
import SwiftUI

/// Pushed from Settings' "Date Format" row: every `DateDisplayFormat`, each showing today's
/// date rendered in that format so the abbreviated pattern (`MM/DD/YYYY`, ...) is legible
/// at a glance rather than requiring the user to decode it themselves.
struct DateFormatPickerView: View {
    @Binding var selection: DateDisplayFormat
    @AppStorage(AppStorageKeys.includeTimeInDates) private var shouldIncludeTime = false

    var body: some View {
        DSGroupedList {
            Section {
                DSToggleRow(title: L10n.Settings.dateFormatShowTime, icon: IconKit.time, isOn: $shouldIncludeTime)
            }
            .listRowBackground(Color.backgroundSecondary)

            Section {
                ForEach(DateDisplayFormat.allCases) { format in
                    SettingsCheckRow(
                        title: format.title,
                        subtitle: format.example(includeTime: shouldIncludeTime),
                        isSelected: format == selection
                    ) {
                        selection = format
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .navigationTitle(L10n.Settings.dateFormatNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .hapticFeedback(.selection, trigger: selection)
    }
}

#Preview {
    NavigationStack {
        DateFormatPickerView(selection: .constant(.slashMonthDayYear))
    }
}
