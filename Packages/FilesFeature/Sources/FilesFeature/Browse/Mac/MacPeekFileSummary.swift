#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let pictureSize: CGFloat = 160
        static let noticeIconSize: CGFloat = .size16
    }

    struct MacPeekFallback: Equatable {
        let item: FileItem
        let serverURL: URL
    }

    extension EnvironmentValues {
        @Entry var macPeekFallback: MacPeekFallback?
    }

    struct MacPeekFileSummary: View {
        let item: FileItem
        let serverURL: URL
        var message: String?
        var onRetry: (() -> Void)?

        @State private var openWith: MacOpenWithModel

        init(item: FileItem, serverURL: URL, message: String? = nil, onRetry: (() -> Void)? = nil) {
            self.item = item
            self.serverURL = serverURL
            self.message = message
            self.onRetry = onRetry
            _openWith = State(initialValue: MacOpenWithModel(source: .remote(item, serverURL: serverURL)))
        }

        private var facts: String {
            [item.previewTypeText, item.size > .zero ? FileSizeFormat.string(item.size) : nil]
                .compactMap(\.self)
                .joined(separator: MacPeekMetrics.separator)
        }

        var body: some View {
            VStack(spacing: .space12) {
                MacFileTile(item: item, serverURL: serverURL, size: Metrics.pictureSize, shouldShowPlayBadge: false)
                    .accessibilityHidden(true)
                Text(item.name)
                    .type(.subtitle1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.top, .space4)
                Text(facts)
                    .type(.body3(.regular), style: .secondary)
                    .monospacedDigit()
                if let notice = openWith.errorMessage ?? message {
                    Label {
                        Text(notice)
                    } icon: {
                        IconKit.warning
                            .resizable()
                            .scaledToFit()
                            .frame(width: Metrics.noticeIconSize, height: Metrics.noticeIconSize)
                            .foregroundStyle(Color.negative)
                    }
                    .type(.body3(.regular), style: .secondary)
                    .multilineTextAlignment(.center)
                }
                actions
                    .padding(.top, .space8)
            }
            .padding(.space24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var actions: some View {
            HStack(spacing: .space12) {
                if let onRetry {
                    Button(L10n.Common.retry, action: onRetry)
                        .buttonStyle(.macDS(.secondary, size: .small))
                }
                if let preferred = openWith.apps?.preferred {
                    Button {
                        openWith.open(with: nil)
                    } label: {
                        Label {
                            Text(L10n.OpenWith.openIn(preferred.name))
                        } icon: {
                            preferred.icon
                        }
                    }
                    .buttonStyle(.macDS(.primary, size: .small))
                    .disabled(openWith.isWorking)
                }
            }
        }
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")

        static func item(_ name: String, kind: String, size: Int64 = 3_100_000) -> FileItem {
            FileItem(name: name, path: "Documents", dateModified: .distantPast, size: size, kind: kind)
        }

        @MainActor
        static func summary(_ item: FileItem, message: String? = nil, onRetry: (() -> Void)? = nil) -> some View {
            MacPeekFileSummary(item: item, serverURL: serverURL, message: message, onRetry: onRetry)
                .frame(width: MacPeekMetrics.previewWidth, height: MacPeekMetrics.previewHeight)
                .background(Color.macCard)
        }
    }

    #Preview("No preview") {
        PreviewFixture.summary(PreviewFixture.item("Keynote deck.key", kind: "key"))
    }

    #Preview("Image failed") {
        PreviewFixture.summary(
            PreviewFixture.item("Beach.jpg", kind: "jpg"),
            message: L10n.Gallery.loadFailed,
            onRetry: {}
        )
    }

    #Preview("Unknown size") {
        PreviewFixture.summary(PreviewFixture.item("invoice.pdf", kind: "pdf", size: .zero))
    }

    #Preview("Long name") {
        PreviewFixture.summary(
            PreviewFixture.item("Quarterly planning workshop notes final revised version two.docx", kind: "docx"),
            message: L10n.EmptyState.loadFailed,
            onRetry: {}
        )
    }
#endif
