#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let iconSize: CGFloat = .iconSmall
        static let chevronSize: CGFloat = .iconXSmall
    }

    public struct MacFormIconLabel: View {
        private let title: String
        private let icon: Image

        public init(_ title: String, icon: Image) {
            self.title = title
            self.icon = icon
        }

        public var body: some View {
            HStack(spacing: .space12) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .foregroundStyle(Color.accent)
                    .accessibilityHidden(true)
                Text(title)
            }
        }
    }

    public struct MacFormLinkRow: View {
        public enum Destination {
            case inApp
            case external

            var accessory: Image {
                switch self {
                case .inApp: IconKit.chevronRight
                case .external: IconKit.externalLink
                }
            }
        }

        private let title: String
        private let icon: Image
        private let destination: Destination
        private let action: () -> Void

        public init(
            _ title: String,
            icon: Image,
            destination: Destination = .inApp,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.icon = icon
            self.destination = destination
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                MacFormRow {
                    MacFormIconLabel(title, icon: icon)
                } control: {
                    destination.accessory
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                        .foregroundStyle(Color.macChromeSecondary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.macChromeText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
        }
    }

    #Preview("Link rows") {
        MacFormPage {
            MacFormGroup {
                MacFormLinkRow("Privacy Policy", icon: IconKit.shield, destination: .external) {}
                MacFormLinkRow("Terms of Use", icon: IconKit.document) {}
            }
        }
        .previewCanvas(.settingsPane)
        .background(Color.macCard)
    }
#endif
