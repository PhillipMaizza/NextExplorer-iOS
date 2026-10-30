import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
#if os(iOS)
    import UIKit
#else
    import AppKit
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
/// Glass, correct sizing/spacing, safe-area insets and accessibility for free: the preview
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
        #if os(macOS)
            // A sheet on the Mac shows no NavigationStack toolbar, so the chrome is a bar of its
            // own across the top, like Preview's title bar.
            content.safeAreaInset(edge: .top, spacing: 0) { macBar }
        #else
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
                            .accessibilityLabelWithTooltip(L10n.PreviewToolbar.close)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        if hasSystemShare {
                            SystemShareButton(source: systemShare)
                        }
                        if let onShareLink {
                            Button { onShareLink() } label: { IconKit.shareLink.foregroundStyle(Color.primaryDS) }
                                .accessibilityLabelWithTooltip(L10n.PreviewToolbar.createShareLink)
                        }
                        if let onRename {
                            Button { onRename() } label: { IconKit.rename.foregroundStyle(Color.primaryDS) }
                                .accessibilityLabelWithTooltip(L10n.PreviewToolbar.rename)
                        }
                        if let onDownload {
                            Button { onDownload() } label: { IconKit.download.foregroundStyle(Color.primaryDS) }
                                .accessibilityLabelWithTooltip(L10n.PreviewToolbar.download)
                        }
                        if onDelete != nil {
                            Spacer()
                        }
                        if let onDelete {
                            Button { onDelete() } label: { IconKit.delete.foregroundStyle(Color.negative) }
                                .accessibilityLabelWithTooltip(L10n.PreviewToolbar.delete)
                        }
                    }
                }
        #endif
    }

    #if os(macOS)
        /// Close (Esc) on the leading edge, the file name in the middle, the actions trailing in
        /// plain system glyphs, Delete marked destructive.
        private var macBar: some View {
            HStack(spacing: .space8) {
                Button(action: onClose) {
                    Label { Text(L10n.PreviewToolbar.close) } icon: { IconKit.close }
                }
                .keyboardShortcut(.cancelAction)
                .help(L10n.PreviewToolbar.close)
                Spacer(minLength: .space8)
                if let title {
                    Text(title).font(.headline).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: .space8)
                if hasSystemShare {
                    MacOpenWithMenu(source: systemShare)
                        .fixedSize()
                    SystemShareButton(source: systemShare)
                }
                if let onShareLink {
                    macButton(L10n.PreviewToolbar.createShareLink, icon: IconKit.shareLink, action: onShareLink)
                }
                if let onRename {
                    macButton(L10n.PreviewToolbar.rename, icon: IconKit.rename, action: onRename)
                }
                if let onDownload {
                    macButton(L10n.PreviewToolbar.download, icon: IconKit.download, action: onDownload)
                }
                if let onDelete {
                    macButton(L10n.PreviewToolbar.delete, icon: IconKit.delete, role: .destructive, action: onDelete)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, .space12)
            .padding(.vertical, .space8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }

        private func macButton(_ title: String, icon: Image, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
            Button(role: role, action: action) {
                Label { Text(title) } icon: { icon }
            }
            .help(title)
        }
    #endif
}

/// Hands the file to the system share sheet ("share the actual file", distinct from "create a
/// share link"). Shares an already local file directly, or downloads a server file to the cache
/// first, showing a spinner while it does. iOS shows `UIActivityViewController`; the Mac shows
/// the native share menu (`NSSharingServicePicker`) under the button.
struct SystemShareButton: View {
    let source: SystemShareSource

    @Dependency(\.filesClient) private var filesClient
    @State private var shareURL: IdentifiedURL?
    @State private var isPreparing = false
    @State private var didFail = false
    #if os(macOS)
        @State private var anchor = MacViewAnchor()
    #endif

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
        #if os(macOS)
            Button(action: prepare) {
                Label { Text(L10n.PreviewToolbar.share) } icon: {
                    if isPreparing {
                        ProgressView().controlSize(.small)
                    } else {
                        IconKit.share.foregroundStyle(didFail ? Color.negativeText : Color.primary)
                    }
                }
            }
            .help(L10n.PreviewToolbar.share)
            .disabled(isDisabled)
            .background(MacViewAnchorView(anchor: anchor))
            .onChange(of: shareURL?.id) { _, _ in
                guard let url = shareURL?.url, let view = anchor.view else { return }
                shareURL = nil
                NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        #else
            Button(action: prepare) {
                if isPreparing {
                    DSSpinner()
                } else {
                    IconKit.share.foregroundStyle(didFail ? Color.negative : Color.primaryDS)
                }
            }
            .accessibilityLabelWithTooltip(L10n.PreviewToolbar.share)
            .disabled(isDisabled)
            .sheet(item: $shareURL) { wrapped in
                ActivityShareSheet(items: [wrapped.url])
            }
        #endif
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
    /// The AppKit view under a SwiftUI control, for anchoring a native popover such as the
    /// share menu.
    @MainActor
    final class MacViewAnchor {
        weak var view: NSView?
    }

    struct MacViewAnchorView: NSViewRepresentable {
        let anchor: MacViewAnchor

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            anchor.view = view
            return view
        }

        func updateNSView(_ view: NSView, context _: Context) {
            anchor.view = view
        }
    }
#endif
