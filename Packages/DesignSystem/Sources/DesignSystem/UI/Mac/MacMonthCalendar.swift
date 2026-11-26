#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let cellHeight: CGFloat = .size32
        static let daysInWeek = 7
        static let shownWeeks = 6
        static let navigationSize: CGFloat = .size24
    }

    public struct MacMonthCalendar: View {
        @Binding private var selection: Date
        private let minimum: Date?
        @State private var month: Date?
        @Environment(\.calendar) private var calendar

        public init(selection: Binding<Date>, minimum: Date? = nil) {
            _selection = selection
            self.minimum = minimum
        }

        private var shownMonth: Date {
            month ?? startOfMonth(selection)
        }

        public var body: some View {
            VStack(spacing: .space8) {
                header
                Grid(horizontalSpacing: .zero, verticalSpacing: .space2) {
                    GridRow {
                        ForEach(weekdaySymbols.indices, id: \.self) { index in
                            Text(weekdaySymbols[index])
                                .type(.caption(.regular), style: .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(weeks.indices, id: \.self) { week in
                        GridRow {
                            ForEach(weeks[week], id: \.self) { day in
                                cell(day)
                            }
                        }
                    }
                }
            }
        }

        private var header: some View {
            HStack {
                navigationButton(IconKit.back, by: -1)
                    .disabled(minimum.map { startOfMonth($0) >= shownMonth } ?? false)
                Spacer()
                Text(shownMonth.formatted(.dateTime.month(.wide).year()))
                    .type(.body2(.semibold))
                Spacer()
                navigationButton(IconKit.chevronRight, by: 1)
            }
        }

        private func navigationButton(_ icon: Image, by months: Int) -> some View {
            Button {
                month = calendar.date(byAdding: .month, value: months, to: shownMonth)
            } label: {
                icon
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.navigationSize, height: Constants.navigationSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .macDisabledDim()
        }

        private func cell(_ day: Date) -> some View {
            let isInMonth = calendar.isDate(day, equalTo: shownMonth, toGranularity: .month)
            let isSelected = calendar.isDate(day, inSameDayAs: selection)
            let isAllowed = minimum.map { calendar.startOfDay(for: $0) <= day } ?? true
            return Button {
                select(day)
            } label: {
                Text(day.formatted(.dateTime.day()))
                    .type(.body3(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected
                        ? Color.onAccent
                        : isInMonth && isAllowed ? Color.primaryDS : Color.tertiaryDS)
                        .frame(maxWidth: .infinity, minHeight: Constants.cellHeight)
                        .background(
                            RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                                .fill(isSelected ? Color.accent : Color.clear)
                        )
                        .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isAllowed)
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private func select(_ day: Date) {
            selection = Self.date(picking: day, keepingTimeOf: selection, minimum: minimum, calendar: calendar)
            if !calendar.isDate(day, equalTo: shownMonth, toGranularity: .month) {
                month = startOfMonth(day)
            }
        }

        nonisolated static func date(
            picking day: Date,
            keepingTimeOf time: Date,
            minimum: Date?,
            calendar: Calendar
        ) -> Date {
            let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
            let picked = calendar.date(
                bySettingHour: clock.hour ?? .zero,
                minute: clock.minute ?? .zero,
                second: clock.second ?? .zero,
                of: day
            ) ?? day
            guard let minimum, picked < minimum else { return picked }
            return calendar.nextDate(
                after: minimum,
                matching: DateComponents(minute: .zero),
                matchingPolicy: .nextTime
            ) ?? minimum
        }

        private var weekdaySymbols: [String] {
            let symbols = calendar.shortStandaloneWeekdaySymbols
            let first = calendar.firstWeekday - 1
            return Array(symbols[first...] + symbols[..<first])
        }

        private var weeks: [[Date]] {
            let first = shownMonth
            let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + Constants.daysInWeek)
                % Constants.daysInWeek
            let start = calendar.date(byAdding: .day, value: -offset, to: first) ?? first
            return (0 ..< Constants.shownWeeks).map { week in
                (0 ..< Constants.daysInWeek).compactMap { weekday in
                    calendar.date(byAdding: .day, value: week * Constants.daysInWeek + weekday, to: start)
                }
            }
        }

        private func startOfMonth(_ date: Date) -> Date {
            calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    #Preview("Month calendar") {
        @Previewable @State var date = Date.now
        MacMonthCalendar(selection: $date, minimum: .now)
            .previewCanvasWidth(.control)
    }
#endif
