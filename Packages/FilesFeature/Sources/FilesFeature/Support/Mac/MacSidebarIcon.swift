#if os(macOS)
    import DesignSystem
    import SwiftUI

    private enum Constants {
        /// One glyph column for every row, so titles line up whatever the glyph's own width.
        static let columnWidth: CGFloat = 20
    }

    struct MacSidebarIcon: View {
        let image: Image
        var isAccented = false
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            image
                .imageScale(.medium)
                .frame(width: Constants.columnWidth)
                .foregroundStyle(isAccented ? colorScheme == .light ? Color.accentText : .accent : Color.primaryDS)
        }
    }

    #Preview {
        VStack(alignment: .leading) {
            MacSidebarIcon(image: IconKit.folder, isAccented: true)
            MacSidebarIcon(image: IconKit.star)
        }
        .previewCanvas(.control)
    }
#endif
