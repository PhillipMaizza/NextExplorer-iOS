#if os(macOS)
    import Localization
    import SwiftUI

    /// The top of a Mac folder browsing sheet: a back button, the title with the current path
    /// under it, and optional trailing controls such as a search field.
    public struct MacSheetHeader<Trailing: View>: View {
        let title: String
        var subtitle: String?
        let canGoBack: Bool
        var backLabel = L10n.Common.back
        let onBack: () -> Void
        @ViewBuilder var trailing: () -> Trailing

        public init(
            title: String,
            subtitle: String? = nil,
            canGoBack: Bool,
            backLabel: String = L10n.Common.back,
            onBack: @escaping () -> Void,
            @ViewBuilder trailing: @escaping () -> Trailing
        ) {
            self.title = title
            self.subtitle = subtitle
            self.canGoBack = canGoBack
            self.backLabel = backLabel
            self.onBack = onBack
            self.trailing = trailing
        }

        public var body: some View {
            HStack(spacing: .space8) {
                Button(action: onBack) { IconKit.back }
                    .disabled(!canGoBack)
                    .accessibilityLabelWithTooltip(backLabel)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.headline).lineLimit(1).truncationMode(.head)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer()
                trailing()
            }
        }
    }

    public extension MacSheetHeader where Trailing == EmptyView {
        init(title: String, subtitle: String? = nil, canGoBack: Bool, backLabel: String = L10n.Common.back, onBack: @escaping () -> Void) {
            self.init(title: title, subtitle: subtitle, canGoBack: canGoBack, backLabel: backLabel, onBack: onBack) { EmptyView() }
        }
    }

    /// A file or folder name with its icon, for Mac tables and lists: the accent folder or the
    /// secondary document glyph, and an optional path under the name.
    public struct MacItemLabel: View {
        let name: String
        var subtitle: String?
        let isDirectory: Bool

        public init(name: String, subtitle: String? = nil, isDirectory: Bool) {
            self.name = name
            self.subtitle = subtitle
            self.isDirectory = isDirectory
        }

        public var body: some View {
            Label {
                VStack(alignment: .leading) {
                    Text(name).lineLimit(1).truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                }
            } icon: {
                (isDirectory ? IconKit.folderFill : IconKit.document)
                    .foregroundStyle(isDirectory ? Color.accent : Color.secondary)
            }
        }
    }

    #Preview("Header") {
        VStack(spacing: .space16) {
            MacSheetHeader(title: "Move “report.pdf”", subtitle: "Documents/Reports", canGoBack: true, onBack: {}) {
                TextField("Search", text: .constant("")).textFieldStyle(.roundedBorder)
            }
            MacSheetHeader(title: "Choose Items", canGoBack: false, onBack: {})
        }
        .padding(.space16)
        .previewCanvasWidth(.sheet)
    }

    #Preview("Item labels") {
        List {
            MacItemLabel(name: "Projects", isDirectory: true)
            MacItemLabel(name: "Reports", subtitle: "Documents/Work", isDirectory: true)
            MacItemLabel(name: "notes.txt", isDirectory: false)
        }
        .previewCanvas(.control)
    }
#endif
