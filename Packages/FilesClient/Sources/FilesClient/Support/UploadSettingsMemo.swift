import CoreModels
import Foundation
import Synchronization

final class UploadSettingsMemo: Sendable {
    private let settings = Mutex<[String: UploadSettings?]>([:])

    func settings(for serverURL: URL, fetch: () async -> UploadSettings?) async -> UploadSettings? {
        if let known = settings.withLock({ $0[serverURL.absoluteString] }) {
            return known
        }
        return await refresh(for: serverURL, fetch: fetch)
    }

    func refresh(for serverURL: URL, fetch: () async -> UploadSettings?) async -> UploadSettings? {
        let fetched = await fetch()
        settings.withLock { $0[serverURL.absoluteString] = .some(fetched) }
        return fetched
    }
}
