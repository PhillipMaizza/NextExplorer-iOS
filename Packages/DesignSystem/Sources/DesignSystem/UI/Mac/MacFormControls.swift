#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let fieldHeight: CGFloat = 34
        static let compactFieldHeight: CGFloat = 28
        static let popupHeight: CGFloat = .size32
        static let calendarWidth: CGFloat = 280
        static let focusHaloWidth: CGFloat = 3
        static let focusHaloOpacity: Double = 0.32
        static let shape = RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
    }

    public struct MacTextField: View {
        private let title: String
        @Binding private var text: String
        private let prompt: String?
        private let isInvalid: Bool
        @FocusState private var isFocused: Bool

        public init(_ title: String, text: Binding<String>, prompt: String? = nil, isInvalid: Bool = false) {
            self.title = title
            _text = text
            self.prompt = prompt
            self.isInvalid = isInvalid
        }

        public var body: some View {
            TextField(title, text: $text, prompt: prompt.map { Text($0).foregroundStyle(Color.macChromeSecondary) })
                .textFieldStyle(.plain)
                .labelsHidden()
                .type(.body2(.regular))
                .focused($isFocused)
                .padding(.horizontal, .space12)
                .macFieldChrome(isFocused: isFocused, isInvalid: isInvalid)
        }
    }

    public enum MacFieldSize {
        case regular
        case compact
        case flexible

        var height: CGFloat? {
            switch self {
            case .regular: Constants.fieldHeight
            case .compact: Constants.compactFieldHeight
            case .flexible: nil
            }
        }
    }

    public extension View {
        func macFieldChrome(isFocused: Bool, isInvalid: Bool = false, size: MacFieldSize = .regular) -> some View {
            let ring = isInvalid ? Color.negative : Color.accent
            return tint(Color.accent)
                .padding(.vertical, size == .flexible ? .space4 : .zero)
                .frame(height: size.height)
                .background(Constants.shape.fill(Color.macField))
                .background(
                    Constants.shape
                        .stroke(
                            ring.opacity(Constants.focusHaloOpacity),
                            lineWidth: Constants.focusHaloWidth
                        )
                        .opacity(isFocused ? 1 : 0)
                )
                .overlay(
                    Constants.shape.strokeBorder(
                        isInvalid || isFocused ? ring : .macLine,
                        lineWidth: .borderWidthHairline
                    )
                )
                .focusEffectDisabled()
                .macDisabledDim()
        }
    }

    public struct MacPopup<Value: Hashable, Options: View>: View {
        private let title: String
        private let valueLabel: String
        @Binding private var selection: Value
        private let options: () -> Options
        private let shouldFillWidth: Bool

        public init(
            _ title: String,
            valueLabel: String,
            selection: Binding<Value>,
            shouldFillWidth: Bool = false,
            @ViewBuilder options: @escaping () -> Options
        ) {
            self.title = title
            self.valueLabel = valueLabel
            _selection = selection
            self.shouldFillWidth = shouldFillWidth
            self.options = options
        }

        public var body: some View {
            MacPopupMenu(title, valueLabel: valueLabel, shouldFillWidth: shouldFillWidth) {
                ForEach(subviews: options()) { option in
                    if let value = option.containerValues.tag(for: Value.self) {
                        Toggle(
                            isOn: Binding(
                                get: { selection == value },
                                set: { _ in selection = value }
                            )
                        ) {
                            option
                        }
                    }
                }
                .toggleStyle(.automatic)
            }
        }
    }

    public struct MacPopupMenu<Items: View>: View {
        private let title: String
        private let valueLabel: String
        private let items: () -> Items
        private let shouldFillWidth: Bool

        public init(
            _ title: String,
            valueLabel: String,
            shouldFillWidth: Bool = false,
            @ViewBuilder items: @escaping () -> Items
        ) {
            self.title = title
            self.valueLabel = valueLabel
            self.shouldFillWidth = shouldFillWidth
            self.items = items
        }

        public var body: some View {
            Menu(content: items) {
                MacPopupLabel(valueLabel: valueLabel, shouldFillWidth: shouldFillWidth)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: !shouldFillWidth, vertical: true)
            .macDisabledDim()
            .accessibilityLabel(title)
            .accessibilityValue(valueLabel)
        }
    }

    public struct MacDatePopup: View {
        private let title: String
        @Binding private var date: Date
        private let range: PartialRangeFrom<Date>
        @State private var isPresented = false

        public init(_ title: String, date: Binding<Date>, in range: PartialRangeFrom<Date>) {
            self.title = title
            _date = date
            self.range = range
        }

        public var body: some View {
            Button {
                isPresented.toggle()
            } label: {
                MacPopupLabel(
                    valueLabel: date.formatted(date: .abbreviated, time: .shortened),
                    shouldFillWidth: false
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityValue(date.formatted(date: .long, time: .shortened))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: .space12) {
                    MacMonthCalendar(selection: $date, minimum: range.lowerBound)
                    DatePicker(title, selection: $date, in: range, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.stepperField)
                }
                .labelsHidden()
                .tint(Color.accent)
                .frame(width: Constants.calendarWidth)
                .padding(.space16)
            }
        }
    }

    private struct MacPopupLabel: View {
        let valueLabel: String
        let shouldFillWidth: Bool

        var body: some View {
            HStack(spacing: .space8) {
                Text(valueLabel)
                    .type(.body2(.regular))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: shouldFillWidth ? .infinity : nil, alignment: .leading)
                IconKit.chevronUpDown
                    .imageScale(.small)
                    .foregroundStyle(Color.macChromeSecondary)
            }
            .padding(.leading, .space12)
            .padding(.trailing, .space8)
            .frame(height: Constants.popupHeight)
            .background(Constants.shape.fill(Color.macField))
            .overlay(Constants.shape.strokeBorder(Color.macLine, lineWidth: .borderWidthHairline))
            .contentShape(Constants.shape)
        }
    }

    #Preview("Date popup") {
        MacDatePopup(
            "Expires",
            date: .constant(Date(timeIntervalSinceReferenceDate: 815_000_000)),
            in: Date.distantPast...
        )
        .padding(.space24)
    }

    #Preview("Field and popup") {
        HStack(spacing: .space8) {
            MacTextField("Search", text: .constant(""), prompt: "A name or a path")
                .previewCanvasWidth(.control)
            MacPopup("Kind", valueLabel: "Any kind", selection: .constant(0)) {
                Text(verbatim: "Any kind").tag(0)
                Text(verbatim: "Uploaded").tag(1)
            }
            MacPopup("Outcome", valueLabel: "Any outcome", selection: .constant(0)) {
                Text(verbatim: "Any outcome").tag(0)
            }
            .disabled(true)
        }
        .padding()
        .background(Color.macCard)
    }
#endif
