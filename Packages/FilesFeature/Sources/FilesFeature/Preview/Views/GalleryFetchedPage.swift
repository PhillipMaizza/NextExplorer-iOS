import DesignSystem
import FilesClient
import FolderPickerFeature
import Localization
import SwiftUI

/// A gallery page's fetch as one value: loading, the fetched value, or the reason it failed.
enum GalleryLoadPhase<Value: Equatable>: Equatable {
    case loading
    case loaded(Value)
    case failed(String)
}

/// A gallery page whose content is fetched first (a document's local file, a text file's text).
/// It fetches only while near the page on screen and lets go of the content when swiped far away,
/// so a long folder never holds a viewer per page; a value the preview already fetched on open is
/// shown at once. A failure offers a retry; a cancelled fetch (swiped away) is not a failure.
struct GalleryFetchedPage<Value: Equatable & Sendable, Content: View>: View {
    let isNear: Bool
    var preloaded: Value?
    /// Shown when the error carries no message of its own.
    let failureMessage: String
    let fetch: @Sendable () async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var phase: GalleryLoadPhase<Value> = .loading
    /// Bumped by Retry so the load task runs again.
    @State private var attempt = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                DSSpinner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(value):
                content(value)
            case let .failed(message):
                PreviewErrorView(message: message) {
                    phase = .loading
                    attempt += 1
                }
            }
        }
        .task(id: "\(isNear)\u{0}\(attempt)") { await load() }
    }

    @MainActor
    private func load() async {
        guard isNear else {
            phase = .loading
            return
        }
        guard phase == .loading else { return }
        if let preloaded {
            phase = .loaded(preloaded)
            return
        }
        // Through `apiResult`, so a 401 signs the user out instead of offering a Retry that fails again;
        // a cancelled fetch throws and is not a failure.
        guard let result = try? await apiResult(fetch), !Task.isCancelled else { return }
        switch result {
        case let .success(value):
            phase = .loaded(value)
        case let .failure(error):
            // A transport error carries no message of its own worth showing over the page's.
            if case .network = error {
                phase = .failed(failureMessage)
            } else {
                phase = .failed(error.userMessage)
            }
        }
    }
}

private enum PreviewFetchError: Error {
    case unreachable
}

#Preview("Loaded") {
    GalleryFetchedPage(isNear: true, preloaded: "Hello", failureMessage: L10n.TextPreview.loadFailed) {
        "Hello"
    } content: { Text(verbatim: $0) }
}

#Preview("Loading") {
    GalleryFetchedPage(isNear: true, failureMessage: L10n.TextPreview.loadFailed) {
        try await Task.sleep(for: .seconds(3_600))
        return "Hello"
    } content: { Text(verbatim: $0) }
}

#Preview("Error") {
    GalleryFetchedPage(isNear: true, failureMessage: L10n.TextPreview.loadFailed) { () throws -> String in
        throw PreviewFetchError.unreachable
    } content: { Text(verbatim: $0) }
}
