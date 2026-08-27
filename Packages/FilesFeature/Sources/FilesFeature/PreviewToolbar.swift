import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import SwiftUI
import UIKit

private enum ToolbarMetrics {
    static let iconSize: CGFloat = .iconMedium
    static let itemPadding: CGFloat = .space12
    static let capsuleVerticalPadding: CGFloat = .space4
    static let capsuleHorizontalPadding: CGFloat = .space4
}

/// The single frosted capsule that holds a full-screen preview's actions (system share,
/// create-share-link, download, delete) — iOS Photos / Files style, one control rather than
/// a row of separate buttons.
struct PreviewActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.horizontal, ToolbarMetrics.capsuleHorizontalPadding)
        .padding(.vertical, ToolbarMetrics.capsuleVerticalPadding)
        .dsGlass()
    }
}

/// One icon action inside a `PreviewActionBar`. Background lives on the bar, not the button.
struct PreviewChipButton: View {
    let icon: Image
    var tint: Color = .primaryDS
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(width: ToolbarMetrics.iconSize, height: ToolbarMetrics.iconSize)
                .padding(ToolbarMetrics.itemPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
    }
}

/// Hands the file to the system share sheet (`UIActivityViewController`) — "share the actual
/// file", distinct from the app's "create a share link" action. Either shares an
/// already-local file directly, or downloads a server file to the cache first.
struct SystemShareButton: View {
    private enum Source {
        case local(URL?)
        case remote(item: FileItem, serverURL: URL)
    }

    private let source: Source
    private let tint: Color

    /// Share an already-downloaded local file. `nil` disables the button.
    init(localFileURL: URL?, tint: Color = .primaryDS) {
        self.source = .local(localFileURL)
        self.tint = tint
    }

    /// Download `item` from the server to the cache, then share it.
    init(item: FileItem, serverURL: URL, tint: Color = .primaryDS) {
        self.source = .remote(item: item, serverURL: serverURL)
        self.tint = tint
    }

    @Dependency(\.filesClient) private var filesClient
    @State private var shareURL: IdentifiedURL?
    @State private var isPreparing = false
    @State private var didFail = false

    private var isDisabled: Bool {
        if case .local(nil) = source { return true }
        return isPreparing
    }

    var body: some View {
        Button {
            switch source {
            case let .local(url):
                if let url { shareURL = IdentifiedURL(url: url) }
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
        } label: {
            Group {
                if isPreparing {
                    ProgressView().tint(tint)
                } else {
                    IconKit.share.resizable().scaledToFit()
                }
            }
            .foregroundStyle(didFail ? Color.negative : tint)
            .frame(width: ToolbarMetrics.iconSize, height: ToolbarMetrics.iconSize)
            .padding(ToolbarMetrics.itemPadding)
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.4 : 1)
        }
        .buttonStyle(DSHapticButtonStyle())
        .allowsHitTesting(!isDisabled)
        .sheet(item: $shareURL) { wrapped in
            ActivityShareSheet(items: [wrapped.url])
        }
    }
}

struct IdentifiedURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
