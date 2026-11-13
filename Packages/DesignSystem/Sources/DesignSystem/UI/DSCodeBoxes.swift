import SwiftUI

/// One box per digit of an authenticator code. A real text field sits invisibly over the boxes, so
/// typing, pasting, AutoFill from Messages and the one time code suggestion all work as they do in
/// any text field, and a tap anywhere on the boxes focuses it.
public struct DSCodeBoxes: View {
    @Binding private var code: String
    private var isFocused: FocusState<Bool>.Binding
    private let length: Int
    private let isInvalid: Bool
    private let accessibilityLabel: String
    private let accessibilityIdentifier: String

    public init(
        code: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        length: Int,
        isInvalid: Bool,
        accessibilityLabel: String,
        accessibilityIdentifier: String
    ) {
        _code = code
        self.isFocused = isFocused
        self.length = length
        self.isInvalid = isInvalid
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private enum Constants {
        static let boxWidth: CGFloat = .size48
        static let boxHeight: CGFloat = .size56
        static let idleBorderWidth: CGFloat = 1
        static let activeBorderWidth: CGFloat = 2
        static let idleBorderOpacity: Double = 0.35
        static let focusAnimationDuration: Double = 0.15
    }

    private var activeIndex: Int {
        min(code.count, length - 1)
    }

    public var body: some View {
        HStack(spacing: .space8) {
            ForEach(0 ..< length, id: \.self) { index in
                box(at: index)
            }
        }
        .frame(maxWidth: .infinity)
        // The hidden field is only as tall as one line of text, so a tap on the rest of a box
        // would miss it. The boxes take the tap themselves and hand focus to the field.
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
        .overlay {
            TextField(text: $code) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .foregroundStyle(Color.clear)
            .tint(Color.clear)
            .textContentType(.oneTimeCode)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
                .focused(isFocused)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .animation(.easeInOut(duration: Constants.focusAnimationDuration), value: code)
        .animation(.easeInOut(duration: Constants.focusAnimationDuration), value: isFocused.wrappedValue)
    }

    private func box(at index: Int) -> some View {
        let digits = Array(code)
        let isActive = isFocused.wrappedValue && index == activeIndex
        return Text(verbatim: index < digits.count ? String(digits[index]) : "")
            .type(.headline3)
            .frame(width: Constants.boxWidth, height: Constants.boxHeight)
            .background(
                Color.backgroundSecondary,
                in: RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                    .strokeBorder(
                        borderColor(isActive: isActive),
                        lineWidth: isActive || isInvalid ? Constants.activeBorderWidth : Constants.idleBorderWidth
                    )
            }
            .accessibilityHidden(true)
    }

    private func borderColor(isActive: Bool) -> Color {
        if isInvalid {
            return .negative
        }
        return isActive ? .accent : Color.secondaryDS.opacity(Constants.idleBorderOpacity)
    }
}

#if DEBUG
    private enum PreviewConstants {
        static let length = 6
    }

    private struct BoxesPreview: View {
        @State var code: String
        let isInvalid: Bool
        @FocusState private var isFocused: Bool

        var body: some View {
            DSCodeBoxes(
                code: $code,
                isFocused: $isFocused,
                length: PreviewConstants.length,
                isInvalid: isInvalid,
                accessibilityLabel: "Code",
                accessibilityIdentifier: "preview.code"
            )
            .padding(.space16)
            .background(Color.backgroundPrimary)
            .task { isFocused = true }
        }
    }

    #Preview("Empty") {
        BoxesPreview(code: "", isInvalid: false)
    }

    #Preview("Partly typed") {
        BoxesPreview(code: "123", isInvalid: false)
    }

    #Preview("Full") {
        BoxesPreview(code: "123456", isInvalid: false)
    }

    #Preview("Wrong code") {
        BoxesPreview(code: "", isInvalid: true)
    }
#endif
