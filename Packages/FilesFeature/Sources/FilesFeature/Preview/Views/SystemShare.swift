import CoreModels
import DesignSystem
import Localization
import SwiftUI
#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// What the system share button hands to `UIActivityViewController`: a file already on disk,
/// or one that has to be downloaded from the server first. `.unavailable` omits the button.
enum SystemShareSource {
    case remote(FileItem, serverURL: URL)
    case local(URL?)
    case unavailable

    /// Which file this shares, so a control can drop a share still preparing for another one.
    var fileID: String? {
        switch self {
        case let .remote(item, _):
            item.id
        case let .local(url):
            url?.path
        case .unavailable:
            nil
        }
    }
}

/// Hands the file to the system share sheet ("share the actual file", distinct from "create a
/// share link"). Shares an already local file directly, or downloads a server file to the cache
/// first, showing a spinner while it does. iOS shows `UIActivityViewController`; the Mac shows
/// the native share menu (`NSSharingServicePicker`) under the button.
struct SystemShareButton: View {
    let source: SystemShareSource

    @State private var model = SystemShareModel()
    #if os(macOS)
        @State private var anchor = MacViewAnchor()
    #endif

    private var canShareFile: Bool {
        if case .unavailable = source {
            return false
        }
        return true
    }

    #if os(iOS)
        @ViewBuilder
        private var shareIcon: some View {
            if model.isPreparing {
                DSSpinner()
            } else {
                IconKit.share.foregroundStyle(model.didFail ? Color.negative : Color.primaryDS)
            }
        }
    #endif

    private var isDisabled: Bool {
        if case .local(nil) = source {
            return true
        }
        if case .unavailable = source {
            return true
        }
        return model.isPreparing
    }

    var body: some View {
        #if os(macOS)
            Button { model.prepare(source) } label: {
                Label { Text(L10n.PreviewToolbar.share) } icon: {
                    if model.isPreparing {
                        MacSpinner()
                    } else {
                        IconKit.share.foregroundStyle(model.didFail ? Color.negativeText : Color.primaryDS)
                    }
                }
            }
            .help(L10n.PreviewToolbar.share)
            // The red glyph alone says the file couldn't be fetched; VoiceOver hears it too.
            .accessibilityValue(model.didFail ? L10n.OpenWith.failed : "")
            .disabled(isDisabled)
            .background(MacViewAnchorView(anchor: anchor))
            .onChange(of: model.shareURL?.id) { _, _ in
                guard let url = model.shareURL?.url, let view = anchor.view else { return }
                model.shareURL = nil
                NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
            .onDisappear { model.cancel() }
            .onChange(of: source.fileID) { model.cancel() }
        #else
            Group {
                if canShareFile {
                    Button { model.prepare(source) } label: { shareIcon }
                        .disabled(isDisabled)
                }
            }
            .accessibilityLabelWithTooltip(L10n.PreviewToolbar.share)
            .accessibilityValue(model.didFail ? L10n.OpenWith.failed : "")
            .systemShareSheet(model)
            .onDisappear { model.cancel() }
            .onChange(of: source.fileID) { model.cancel() }
        #endif
    }
}

struct IdentifiedURL: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
    extension View {
        /// Presents the system share sheet once `model` has the file on disk.
        func systemShareSheet(_ model: SystemShareModel) -> some View {
            sheet(item: Binding(get: { model.shareURL }, set: { model.shareURL = $0 })) { wrapped in
                ActivityShareSheet(items: [wrapped.url])
                    .systemSharePresentation()
                    .accessibilityIdentifier(AccessibilityIdentifiers.Share.sheet)
            }
        }

        /// Presents the system share sheet for files kept on the device.
        func keptFilesShareSheet(_ share: KeptFilesShare?, onDismiss: @escaping () -> Void) -> some View {
            sheet(item: Binding(get: { share }, set: {
                if $0 == nil {
                    onDismiss()
                }
            })) { share in
                ActivityShareSheet(items: share.urls).systemSharePresentation()
            }
        }

        /// Half height like the system's own share sheet, where the sheet is frosted glass; the
        /// system goes opaque by itself with Reduce Transparency on.
        private func systemSharePresentation() -> some View {
            ignoresSafeArea()
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
        }
    }

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

#Preview("Server file") {
    SystemShareButton(source: .remote(
        FileItem(name: "report.pdf", path: "Docs", dateModified: .distantPast, size: 2_048, kind: "pdf"),
        serverURL: URL(fileURLWithPath: "/")
    ))
}

#Preview("Local file") {
    SystemShareButton(source: .local(URL(fileURLWithPath: "/tmp/report.pdf")))
}

#Preview("Local file not ready") {
    SystemShareButton(source: .local(nil))
}
