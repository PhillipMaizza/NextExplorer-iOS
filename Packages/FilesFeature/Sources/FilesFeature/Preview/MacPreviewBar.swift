#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    /// The bar across the top of a Mac preview sheet, like Preview's title bar: Close (Esc) on
    /// the leading edge, the file name in the middle, the actions trailing. A Mac sheet shows no
    /// `NavigationStack` toolbar, so every preview draws this instead.
    struct MacPreviewBar<Leading: View, Trailing: View>: View {
        let title: String?
        let onClose: () -> Void
        @ViewBuilder var leading: () -> Leading
        @ViewBuilder var trailing: () -> Trailing

        var body: some View {
            HStack(spacing: .space8) {
                Button(action: onClose) {
                    Label { Text(L10n.PreviewToolbar.close) } icon: { IconKit.close }
                }
                .keyboardShortcut(.cancelAction)
                .help(L10n.PreviewToolbar.close)
                leading()
                Spacer(minLength: .space8)
                if let title {
                    Text(title).font(.headline).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: .space8)
                trailing()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, .space12)
            .padding(.vertical, .space8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    extension View {
        /// Pins a `MacPreviewBar` above the preview's content.
        func macPreviewBar(
            title: String?,
            onClose: @escaping () -> Void,
            @ViewBuilder leading: @escaping () -> some View = { EmptyView() },
            @ViewBuilder trailing: @escaping () -> some View = { EmptyView() }
        ) -> some View {
            safeAreaInset(edge: .top, spacing: 0) {
                MacPreviewBar(title: title, onClose: onClose, leading: leading, trailing: trailing)
            }
        }
    }

    #Preview("Preview bar") {
        Text(verbatim: "notes.txt")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .macPreviewBar(title: "notes.txt", onClose: {}) {
                EmptyView()
            } trailing: {
                Button(L10n.Common.edit) {}
            }
            .previewCanvas(.dialog)
    }
#endif
