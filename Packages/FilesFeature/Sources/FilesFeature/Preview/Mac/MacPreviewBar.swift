#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacPreviewBar<Trailing: View>: View {
        let title: String?
        var file: FileItem?
        let onClose: () -> Void
        @ViewBuilder var trailing: () -> Trailing

        var body: some View {
            HStack(spacing: .space12) {
                if let file {
                    MacFileTile(item: file, size: MacPeekMetrics.iconSize, shouldShowPlayBadge: false)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: .space2) {
                    if let title {
                        Text(title)
                            .type(.subtitle2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let file {
                        Text(file.macPeekFacts)
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: .space8) {
                    trailing()
                    MacIconButton(IconKit.close, label: L10n.PreviewToolbar.close, action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.leading, .space24)
            .padding(.trailing, .space16)
            .padding(.vertical, .space16)
            .background(Color.macCard)
        }
    }

    extension View {
        func macPreviewBar(
            title: String?,
            file: FileItem? = nil,
            onClose: @escaping () -> Void,
            @ViewBuilder trailing: @escaping () -> some View = { EmptyView() }
        ) -> some View {
            safeAreaInset(edge: .top, spacing: 0) {
                MacPreviewBar(title: title, file: file, onClose: onClose, trailing: trailing)
            }
        }
    }

    extension View {
        func macWorking(_ isWorking: Bool) -> some View {
            opacity(isWorking ? .zero : 1)
                .overlay {
                    if isWorking {
                        MacSpinner()
                    }
                }
        }
    }

    #Preview("Name only") {
        Text(verbatim: "notes.txt")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .macPreviewBar(title: "notes.txt", onClose: {}) {
                Button(L10n.Common.edit) {}
                    .buttonStyle(.macDS(.primary))
            }
            .previewCanvas(.dialog)
    }

    #Preview("File") {
        let file = FileItem(name: "Welcome.pdf", path: "", dateModified: Date(), size: 188_416, kind: "pdf")
        Text(verbatim: file.name)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .macPreviewBar(title: file.name, file: file, onClose: {}) {
                MacIconButton(IconKit.link, label: L10n.PreviewToolbar.createShareLink) {}
                MacIconButton(IconKit.ellipsis, label: L10n.Common.more) {}
            }
            .previewCanvas(.dialog)
    }
#endif
