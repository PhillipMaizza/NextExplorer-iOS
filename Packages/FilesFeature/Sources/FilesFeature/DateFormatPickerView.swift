import DesignSystem
import SwiftUI

private enum Constants {
    static let rowSpacing: CGFloat = .space2
    static let checkmarkSize: CGFloat = .iconSmall
    static let checkmarkSpringResponse: Double = 0.3
    static let checkmarkSpringDamping: Double = 0.7
}

/// Pushed from Settings' "Date Format" row: every `DateDisplayFormat`, each showing today's
/// date rendered in that format so the abbreviated pattern (`MM/DD/YYYY`, ...) is legible
/// at a glance rather than requiring the user to decode it themselves.
struct DateFormatPickerView: View {
    @Binding var selection: DateDisplayFormat
    @AppStorage("includeTimeInDates") private var includeTime = false

    var body: some View {
        List {
            Section {
                DSToggleRow(title: "Show Time", icon: IconKit.clock, isOn: $includeTime)
            }
            .listRowBackground(Color.backgroundSecondary)

            Section {
                ForEach(DateDisplayFormat.allCases) { format in
                    Button {
                        selection = format
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Constants.rowSpacing) {
                                Text(format.title).type(.body1(.regular), style: .primary(for: .label))
                                Text(format.example(includeTime: includeTime)).type(.body3(.regular), style: .secondary)
                            }
                            Spacer()
                            if format == selection {
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
                    .animation(.spring(response: Constants.checkmarkSpringResponse, dampingFraction: Constants.checkmarkSpringDamping), value: selection)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
        .navigationTitle("Date Format")
        .navigationBarTitleDisplayMode(.inline)
        .hapticFeedback(.selection, trigger: selection)
    }
}

#Preview {
    NavigationStack {
        DateFormatPickerView(selection: .constant(.slashMonthDayYear))
    }
}
