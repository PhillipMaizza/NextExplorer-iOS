import SwiftUI

private enum Metrics {
    static let phoneTextWidth: CGFloat = 400
    static let tileIconRatio: CGFloat = 0.4375
    static let tileTint: Double = .opacityWash
    static let bulletIconBaselineDrop: CGFloat = 5
}

public struct EmptyGuide<Art: View, Detail: View>: View {
    private let title: String
    private let art: () -> Art
    private let detail: () -> Detail

    public init(title: String, @ViewBuilder art: @escaping () -> Art, @ViewBuilder detail: @escaping () -> Detail) {
        self.title = title
        self.art = art
        self.detail = detail
    }

    public var body: some View {
        #if os(macOS)
            HStack(spacing: .space48) {
                art()
                text
            }
            .padding(.space40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #elseif os(iOS)
            VStack(alignment: .leading, spacing: .space24) {
                art()
                text
            }
            .frame(maxWidth: Metrics.phoneTextWidth, alignment: .leading)
            .padding(.horizontal, .space32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: .space12) {
            Text(title)
                .type(.headline2)
                .foregroundStyle(Color.primaryDS)
            detail()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

public struct EmptyGuideTile: View {
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

public struct EmptyGuideBullet: View {
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
                .guideBulletSquare
                .foregroundStyle(Color.secondaryDS)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Metrics.bulletIconBaselineDrop
                }
                .accessibilityHidden(true)
            Text(text)
                .type(.body1(.regular), style: .secondary)
        }
    }
}

private extension View {
    var guideBulletSquare: some View {
        #if os(macOS)
            macSquare(.iconSmall)
        #elseif os(iOS)
            frame(width: .iconSmall, height: .iconSmall)
        #endif
    }
}

#if os(macOS)
    #Preview("Empty guide") {
        EmptyGuide(title: "Trash is empty") {
            EmptyGuideTile(icon: IconKit.macTrash)
        } detail: {
            EmptyGuideBullet(icon: IconKit.macClock, text: "Items stay here for 30 days.")
            EmptyGuideBullet(icon: IconKit.macRestore, text: "Restore puts an item back where it was.")
        }
        .background(Color.macCard)
        .previewCanvas(.settingsPane)
    }

    #Preview("Empty guide, largest text, dark") {
        EmptyGuide(title: "Nothing shared with you") {
            EmptyGuideTile(icon: IconKit.macSidebarShared)
        } detail: {
            Text(verbatim: "Files people share with you show up here.")
                .type(.body1(.regular), style: .secondary)
        }
        .background(Color.macCard)
        .previewCanvas(.settingsPane)
        .macTextScale(MacTextScale.range.upperBound)
        .environment(\.colorScheme, .dark)
    }
#elseif os(iOS)
    #Preview("Empty guide") {
        EmptyGuide(title: "The trash is empty") {
            EmptyGuideTile(icon: IconKit.delete, size: .size64)
        } detail: {
            EmptyGuideBullet(icon: IconKit.time, text: "Items stay here for 30 days.")
            EmptyGuideBullet(icon: IconKit.restore, text: "Restore puts an item back where it was.")
        }
        .background(Color.backgroundPrimary)
    }

    #Preview("Empty guide, dark") {
        EmptyGuide(title: "Nothing shared with you yet") {
            EmptyGuideTile(icon: IconKit.shareLink, size: .size64)
        } detail: {
            Text(verbatim: "Links other people share with you show up here.")
                .type(.body1(.regular), style: .secondary)
        }
        .background(Color.backgroundPrimary)
        .preferredColorScheme(.dark)
    }
#endif
