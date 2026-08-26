import DesignSystem
import SwiftUI

private enum Constants {
    static let rowSpacing: CGFloat = .space2
    static let checkmarkSize: CGFloat = .iconSmall
}

/// Pushed from Settings' "Date Format" row: every `DateDisplayFormat`, each showing today's
/// date rendered in that format so the abbreviated pattern (`MM/DD/YYYY`, ...) is legible
/// at a glance rather than requiring the user to decode it themselves.
struct DateFormatPickerView: View {
    @Binding var selection: DateDisplayFormat

    var body: some View {
        List {
            ForEach(DateDisplayFormat.allCases) { format in
                Button {
                    selection = format
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Constants.rowSpacing) {
                            Text(format.title).type(.body1(.regular), style: .primary(for: .label))
                            Text(format.example).type(.body3(.regular), style: .secondary)
                        }
                        Spacer()
                        if format == selection {
                            IconKit.checkmark
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.accent)
                                .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .navigationTitle("Date Format")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        DateFormatPickerView(selection: .constant(.slashMonthDayYear))
    }
}
