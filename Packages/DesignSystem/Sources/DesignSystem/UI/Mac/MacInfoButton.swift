#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let iconSize: CGFloat = 13
        static let popoverWidth: CGFloat = 260
    }

    public struct MacInfoButton: View {
        private let lines: [String]
        @State private var isPresented = false

        public init(_ lines: String...) {
            self.lines = lines
        }

        public init(lines: [String]) {
            self.lines = lines
        }

        public var body: some View {
            Button { isPresented.toggle() } label: {
                IconKit.info
                    .resizable()
                    .scaledToFit()
                    .macSquare(Constants.iconSize)
                    .foregroundStyle(Color.macChromeSecondary)
                    .padding(.space2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.moreInfo)
            .help(text)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                Text(text)
                    .type(.body3(.regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Constants.popoverWidth, alignment: .leading)
                    .padding(.space12)
            }
        }

        private var text: String {
            lines.joined(separator: "\n\n")
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
