import ComposableArchitecture
import FilesClient
import FolderPickerFeature
import Foundation

/// Gets a file ready for the system share sheet: a local file at once, a server file after
/// downloading it to the cache. Lives outside the control that starts it, so a menu item (torn
/// down as soon as it is tapped) can start a share as well as a button.
@MainActor
@Observable
final class SystemShareModel {
    /// The file to hand to the share sheet; set once it is on disk.
    var shareURL: IdentifiedURL?
    private(set) var isPreparing = false
    private(set) var didFail = false

    @ObservationIgnored
    @Dependency(\.filesClient) private var filesClient
    /// The running download, cancelled when the control that started it goes away.
    @ObservationIgnored private(set) var download: Task<Void, Never>?

    func prepare(_ source: SystemShareSource) {
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
            let filesClient = filesClient
            download = Task {
                // Through `apiResult`, so a 401 signs the user out like every other request; a
                // cancelled download is not a failure, and `cancel` already ended the preparing.
                let fetch: @Sendable () async throws -> URL = { try await filesClient.downloadRawFile(serverURL, item) }
                let result = try? await apiResult(fetch)
                guard !Task.isCancelled else { return }
                isPreparing = false
                download = nil
                guard let result else { return }
                switch result {
                case let .success(url):
                    shareURL = IdentifiedURL(url: url)
                case .failure:
                    didFail = true
                }
            }
        }
    }

    /// Stops a download still running, so leaving the gallery, or swiping to another file, never
    /// presents a late share sheet for the file left behind, and the next tap starts at once.
    func cancel() {
        download?.cancel()
        download = nil
        isPreparing = false
    }

    func clearFailure() {
        didFail = false
    }
}
