#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let iconSize: CGFloat = 13
    }

    public struct MacInfoButton: View {
        private let lines: [String]

        public init(_ lines: String...) {
            self.lines = lines
        }

        public init(lines: [String]) {
            self.lines = lines
        }

        public var body: some View {
            IconKit.info
                .resizable()
                .scaledToFit()
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .foregroundStyle(Color.macChromeSecondary)
                .padding(.space2)
                .contentShape(Rectangle())
                .accessibilityLabel(L10n.Common.moreInfo)
                .help(lines.joined(separator: "\n\n"))
        }
    }

    public struct MacInfoLabel: View {
        private let title: String
        private let info: [String]

        public init(_ title: String, info: String...) {
            self.title = title
            self.info = info
        }

        public var body: some View {
            HStack(spacing: .space4) {
                Text(title)
                MacInfoButton(lines: info)
            }
        }
    }

    #Preview("Info button") {
        VStack(alignment: .leading, spacing: .space16) {
            MacInfoLabel("Retention (days)", info: "From 1 to 3650 days.")
            MacInfoButton("Each volume keeps its trash in a hidden folder.", "Deleting never copies anything.")
        }
        .padding()
        .previewCanvas(.control)
        .background(Color.macCard)
    }
#endif
