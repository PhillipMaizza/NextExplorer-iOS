import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// Search results split by where they are: kept on this device (a pinned item, anything below a
/// pinned folder, or a file with a stored copy) or only on the server. Each part keeps the server's
/// order. With nothing on the device there is one plain list, as before.
public struct SearchResultSections: Equatable, Sendable {
    public let onDevice: [SearchResultItem]
    public let remote: [SearchResultItem]

    public init(_ results: [SearchResultItem], onDeviceIDs: Set<String>) {
        var onDevice: [SearchResultItem] = []
        var remote: [SearchResultItem] = []
        for result in results {
            if onDeviceIDs.contains(result.id) {
                onDevice.append(result)
            } else {
                remote.append(result)
            }
        }
        self.onDevice = onDevice
        self.remote = remote
    }

    /// Headers show only when something is on the device.
    public var isSplit: Bool {
        !onDevice.isEmpty
    }
}

extension OfflineAvailability {
    /// The results kept on the device, read off the main actor: the store stats files on disk.
    static func onDeviceIDs(of results: [SearchResultItem], in store: OfflineFileStore) async -> Set<String> {
        guard !results.isEmpty else { return [] }
        return await Task.detached(priority: .utility) {
            classify(
                results,
                pinnedPaths: store.pinnedRoots().map(\.path),
                id: \.id,
                isDirectory: \.isDirectory,
                // A hit carries no size or date, so any complete or partial copy counts, like opening it does.
                hasCopy: { store.localURLIgnoringStaleness($0.previewItem(openedAt: .distantPast)) != nil }
            ).all
        }.value
    }
}

extension Effect {
    /// Finds which of `results` are on the device and reports them through `done`; with no results
    /// it clears `ids` at once and stops a lookup still running.
    static func searchOnDevice(
        _ results: [SearchResultItem],
        ids: inout Set<String>,
        store: OfflineFileStore,
        cancelID: some Hashable & Sendable,
        done: @escaping @Sendable (Set<String>) -> Action
    ) -> Self {
        guard !results.isEmpty else {
            ids = []
            return .cancel(id: cancelID)
        }
        return .run { send in
            await send(done(OfflineAvailability.onDeviceIDs(of: results, in: store)))
        }
        .cancellable(id: cancelID, cancelInFlight: true)
    }
}

/// What a screen's lookup of results on the device follows: the results on screen and what the folder
/// keeps offline. A change in either looks again.
struct SearchOnDeviceKey: Equatable {
    let results: [String]?
    let offline: Set<String>
}
