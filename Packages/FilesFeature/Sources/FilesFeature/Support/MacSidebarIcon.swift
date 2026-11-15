#if os(macOS)
    import DesignSystem
    import SwiftUI

    private enum Constants {
        /// One glyph column for every row, so titles line up whatever the glyph's own width.
        static let columnWidth: CGFloat = 20
    }

    /// A sidebar row's glyph: the primary color, white only on the emphasized (blue) selection of
    /// a focused sidebar, and the primary color again on the gray selection it shows while focus
    /// is elsewhere. The Mac keeps the accent out of the sidebar.
    struct MacSidebarIcon: View {
        let image: Image
        @Environment(\.backgroundProminence) private var backgroundProminence

        var body: some View {
            image
                .imageScale(.medium)
                .frame(width: Constants.columnWidth)
                .foregroundStyle(backgroundProminence == .increased ? Color.white : Color.primaryDS)
        }
    }

    #Preview {
        List(selection: .constant(1)) {
            Label { Text(verbatim: "Browse") } icon: { MacSidebarIcon(image: IconKit.folder) }.tag(1)
            Label { Text(verbatim: "Favorites") } icon: { MacSidebarIcon(image: IconKit.star) }.tag(2)
        }
        .listStyle(.sidebar)
        .previewCanvas(.control)
    }
#endif
