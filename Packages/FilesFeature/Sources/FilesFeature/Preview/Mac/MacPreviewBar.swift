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
                HStack(spacing: .space8) {
                    MacIconButton(IconKit.close, label: L10n.PreviewToolbar.close, isFilled: false, action: onClose)
                        .keyboardShortcut(.cancelAction)
                    leading()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let title {
                    Text(title)
                        .type(.body1(.bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                }
                HStack(spacing: .space8) {
                    trailing()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space12)
            .background(Color.macCard)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.macLine)
                    .frame(height: .borderWidthHairline)
            }
        }
    }

    extension View {
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
                    .buttonStyle(.macDS(.primary, size: .small))
            }
            .previewCanvas(.dialog)
    }
#endif
