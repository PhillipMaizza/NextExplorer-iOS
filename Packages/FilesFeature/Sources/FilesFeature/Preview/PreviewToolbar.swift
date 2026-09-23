import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// What the system-share button hands to `UIActivityViewController`: a file already on disk,
/// or one that has to be downloaded from the server first. `.unavailable` omits the button.
enum SystemShareSource {
    case remote(FileItem, serverURL: URL)
    case local(URL?)
    case unavailable
}

/// The chrome every full-screen media preview shares: an inline title, a top-trailing close,
/// and a bottom action bar (system share, create-share-link, download, delete). These are
/// plain `.toolbar` items inside the caller's `NavigationStack`, so the OS gives them Liquid
/// Glass, correct sizing/spacing, safe-area insets and accessibility for free — the preview
/// only supplies the actions.
extension View {
    func previewChrome(
        title: String? = nil,
        systemShare: SystemShareSource = .unavailable,
        onShareLink: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onDownload: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(PreviewChrome(
            title: title,
            systemShare: systemShare,
            onShareLink: onShareLink,
            onRename: onRename,
            onDownload: onDownload,
            onDelete: onDelete,
            onClose: onClose
        ))
    }
}

private struct PreviewChrome: ViewModifier {
    let title: String?
    let systemShare: SystemShareSource
    let onShareLink: (() -> Void)?
    let onRename: (() -> Void)?
    let onDownload: (() -> Void)?
    let onDelete: (() -> Void)?
    let onClose: () -> Void

    private var hasSystemShare: Bool {
        if case .unavailable = systemShare {
            return false
        }
        return true
    }

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackgroundHidden()
            .toolbar {
                if let title {
                    ToolbarItem(placement: .principal) {
                        Text(title).lineLimit(1).truncationMode(.middle)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onClose() } label: { IconKit.close.foregroundStyle(Color.primaryDS) }
                        .accessibilityLabel(L10n.PreviewToolbar.close)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if hasSystemShare {
                        SystemShareButton(source: systemShare)
                    }
                    if let onShareLink {
                        Button { onShareLink() } label: { IconKit.shareLink.foregroundStyle(Color.primaryDS) }
                            .accessibilityLabel(L10n.PreviewToolbar.createShareLink)
                    }
                    if let onRename {
                        Button { onRename() } label: { IconKit.rename.foregroundStyle(Color.primaryDS) }
                            .accessibilityLabel(L10n.PreviewToolbar.rename)
                    }
                    if let onDownload {
                        Button { onDownload() } label: { IconKit.download.foregroundStyle(Color.primaryDS) }
                            .accessibilityLabel(L10n.PreviewToolbar.download)
                    }
                    if onDelete != nil {
                        Spacer()
                    }
                    if let onDelete {
                        Button { onDelete() } label: { IconKit.delete.foregroundStyle(Color.negative) }
                            .accessibilityLabel(L10n.PreviewToolbar.delete)
                    }
                }
            }
    }
}

/// Hands the file to the system share sheet (`UIActivityViewController`) — "share the actual
/// file", distinct from "create a share link". Shares an already-local file directly, or
/// downloads a server file to the cache first, showing a spinner while it does.
struct SystemShareButton: View {
    let source: SystemShareSource

    @Dependency(\.filesClient) private var filesClient
    @State private var shareURL: IdentifiedURL?
    @State private var isPreparing = false
    @State private var didFail = false

    private var isDisabled: Bool {
        if case .local(nil) = source {
            return true
        }
        if case .unavailable = source {
            return true
        }
        return isPreparing
    }

    var body: some View {
        Button(action: prepare) {
            if isPreparing {
                DSSpinner()
            } else {
                IconKit.share.foregroundStyle(didFail ? Color.negative : Color.primaryDS)
            }
        }
        .accessibilityLabel(L10n.PreviewToolbar.share)
        .disabled(isDisabled)
        .sheet(item: $shareURL) { wrapped in
            ActivityShareSheet(items: [wrapped.url])
        }
    }

    private func prepare() {
        switch source {
        case .unavailable:
            break
        case let .local(url):
            if let url {
                shareURL = IdentifiedURL(url: url)
            }
        case let .remote(item, serverURL):
            guard !isPreparing else { return }
            isPreparing = true
            didFail = false
            Task {
                defer { isPreparing = false }
                if let url = try? await filesClient.downloadRawFile(serverURL, item) {
                    shareURL = IdentifiedURL(url: url)
                } else {
                    didFail = true
                }
            }
        }
    }
}

struct IdentifiedURL: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
    private struct ActivityShareSheet: UIViewControllerRepresentable {
        let items: [Any]

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }
#else
    /// A Mac has no activity sheet; the system share menu lives behind a `ShareLink` instead.
    private struct ActivityShareSheet: View {
        let items: [URL]
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: .space16) {
                ForEach(items, id: \.self) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                    }
                }
                Button(L10n.Common.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.space24)
        }
    }
#endif
