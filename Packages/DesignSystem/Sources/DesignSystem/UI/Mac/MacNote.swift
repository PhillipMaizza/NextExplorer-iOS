#if os(macOS)
    import SwiftUI

    public extension EnvironmentValues {
        @Entry var macInsetFill = Color.macRow
    }

    public extension View {
        func macSheetSurface() -> some View {
            environment(\.macInsetFill, .backgroundPrimary)
        }
    }

    public struct MacNote: View {
        public enum Kind: Sendable {
            case error
            case warning
            case info
        }

        private let text: String
        private let kind: Kind
        @Environment(\.macInsetFill) private var fill

        public init(_ text: String, kind: Kind) {
            self.text = text
            self.kind = kind
        }

        public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: .space8) {
                icon
                    .type(.body3(.regular))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(text)
                    .type(.body3(.regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.space12)
            .background(
                RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                    .fill(fill)
            )
            .accessibilityElement(children: .combine)
        }

        private var icon: Image {
            switch kind {
            case .error: IconKit.errorFill
            case .warning: IconKit.warningFill
            case .info: IconKit.infoFill
            }
        }

        private var tint: Color {
            switch kind {
            case .error: .negative
            case .warning: .accent
            case .info: .macChromeSecondary
            }
        }
    }

    #Preview("Notes") {
        VStack(spacing: .space12) {
            MacNote("Could not reach that server. Check the address and try again.", kind: .error)
            MacNote("This connection isn't encrypted. Your password is sent in the clear.", kind: .warning)
            MacNote("Add a port (e.g. :3000).", kind: .info)
        }
        .padding(.space24)
        .frame(width: MacFormSheetMetrics.width)
        .macCard()
    }

    #Preview("Notes in a sheet") {
        MacNote("That code is not right.", kind: .error)
            .padding(.space24)
            .frame(width: MacFormSheetMetrics.width)
            .macSheetSurface()
            .background(Color.macRow)
    }
#endif
