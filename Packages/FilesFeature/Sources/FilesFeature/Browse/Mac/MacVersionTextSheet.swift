#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 560
        static let height: CGFloat = 420
        static let padding: CGFloat = .space16
    }

    /// One version of a text file, read only: what it said, to look at before restoring it.
    struct MacVersionTextSheet: View {
        let preview: VersionTextPreview
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: 0) {
                Text(preview.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metrics.padding)
                Divider()
                ScrollView {
                    Text(preview.content)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Metrics.padding)
                }
                Divider()
                MacDialogButtons(
                    confirmTitle: L10n.Common.close,
                    cancelTitle: nil,
                    onCancel: {},
                    onConfirm: { dismiss() }
                )
                .padding(Metrics.padding)
            }
            .frame(width: Metrics.width, height: Metrics.height)
        }
    }

    #Preview("Text version") {
        MacVersionTextSheet(
            preview: VersionTextPreview(
                id: "v1",
                title: "Nov 17, 2026 at 10:30",
                content: "Line one\nLine two\nLine three"
            )
        )
    }

    #Preview("Empty text version") {
        MacVersionTextSheet(preview: VersionTextPreview(id: "v2", title: "Kept", content: ""))
    }
#endif
