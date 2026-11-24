#if os(macOS)
    import Localization
    import SwiftUI

    public struct MacIconButton: View {
        let icon: Image
        let label: String
        let isFilled: Bool
        let action: () -> Void

        public init(_ icon: Image, label: String, isFilled: Bool = true, action: @escaping () -> Void) {
            self.icon = icon
            self.label = label
            self.isFilled = isFilled
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: .iconSmall, height: .iconSmall)
                    .foregroundStyle(Color.primaryDS)
                    .frame(width: .size40, height: .size40)
                    .background(Circle().fill(isFilled ? Color.macSegment : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabelWithTooltip(label)
        }
    }

    #Preview("Icon buttons") {
        HStack(spacing: .space8) {
            MacIconButton(IconKit.ellipsis, label: L10n.Common.more) {}
            MacIconButton(IconKit.close, label: L10n.Common.close, isFilled: false) {}
        }
        .padding(.space16)
        .background(Color.macCard)
    }
#endif
