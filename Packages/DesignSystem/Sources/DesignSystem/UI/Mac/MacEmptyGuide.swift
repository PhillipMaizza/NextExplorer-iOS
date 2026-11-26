#if os(macOS)
    import SwiftUI

    private enum Metrics {
        static let tileIconRatio: CGFloat = 0.4375
        static let tileTint: Double = .opacityWash
        static let bulletIconBaselineDrop: CGFloat = 5
    }

    public struct MacEmptyGuide<Art: View, Detail: View>: View {
        private let title: String
        private let art: () -> Art
        private let detail: () -> Detail

        public init(title: String, @ViewBuilder art: @escaping () -> Art, @ViewBuilder detail: @escaping () -> Detail) {
            self.title = title
            self.art = art
            self.detail = detail
        }

        public var body: some View {
            HStack(spacing: .space48) {
                art()
                VStack(alignment: .leading, spacing: .space12) {
                    Text(title)
                        .type(.headline2)
                        .foregroundStyle(Color.primaryDS)
                    detail()
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.space40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    public struct MacEmptyGuideTile: View {
        private let icon: Image
        private let size: CGFloat

        public init(icon: Image, size: CGFloat = .size96) {
            self.icon = icon
            self.size = size
        }

        public var body: some View {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: size * Metrics.tileIconRatio, height: size * Metrics.tileIconRatio)
                .foregroundStyle(Color.accentText)
                .frame(width: size, height: size)
                .background(
                    Color.accent.opacity(Metrics.tileTint),
                    in: RoundedRectangle(cornerRadius: size * .tileCornerRatio, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }

    public struct MacEmptyGuideBullet: View {
        private let icon: Image
        private let text: String

        public init(icon: Image, text: String) {
            self.icon = icon
            self.text = text
        }

        public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: .space8) {
                icon
                    .resizable()
                    .scaledToFit()
                    .macSquare(.iconSmall)
                    .foregroundStyle(Color.secondaryDS)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Metrics.bulletIconBaselineDrop
                    }
                    .accessibilityHidden(true)
                Text(text)
                    .type(.body1(.regular), style: .secondary)
            }
        }
    }

    #Preview("Empty guide") {
        MacEmptyGuide(title: "Trash is empty") {
            MacEmptyGuideTile(icon: IconKit.macTrash)
        } detail: {
            MacEmptyGuideBullet(icon: IconKit.macClock, text: "Items stay here for 30 days.")
            MacEmptyGuideBullet(icon: IconKit.macRestore, text: "Restore puts an item back where it was.")
        }
        .background(Color.macCard)
        .previewCanvas(.settingsPane)
    }

    #Preview("Empty guide, largest text, dark") {
        MacEmptyGuide(title: "Nothing shared with you") {
            MacEmptyGuideTile(icon: IconKit.macSidebarShared)
        } detail: {
            Text(verbatim: "Files people share with you show up here.")
                .type(.body1(.regular), style: .secondary)
        }
        .background(Color.macCard)
        .previewCanvas(.settingsPane)
        .macTextScale(MacTextScale.range.upperBound)
        .environment(\.colorScheme, .dark)
    }
#endif
