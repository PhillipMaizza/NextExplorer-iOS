#if os(macOS)
    import DesignSystem
    import SwiftUI

    /// A sidebar row's glyph like Finder's: the accent, white only on the emphasized (blue)
    /// selection of a focused sidebar, and the accent again on the gray selection it shows
    /// while focus is elsewhere.
    struct MacSidebarIcon: View {
        let image: Image
        @Environment(\.backgroundProminence) private var backgroundProminence

        var body: some View {
            image.foregroundStyle(backgroundProminence == .increased ? Color.white : Color.accent)
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
