#if DEBUG
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    import Foundation

    extension UITestSupport {
        /// The signed in account's share links, kept in memory for one app launch so an edit or a
        /// delete from the Shared tab shows in the next listing, as on the server.
        static func installShareMocks(into client: inout FilesClient) {
            let shares = LockIsolated(Share.previewSharedByMe)
            let update = client.updateShareLink
            client.mySharedLinks = { _ in shares.value }
            client.updateShareLink = { serverURL, shareID, request in
                let updated = try await update(serverURL, shareID, request)
                shares.withValue { list in
                    if let index = list.firstIndex(where: { $0.id == shareID }) {
                        list[index] = updated
                    }
                }
                return updated
            }
            client.deleteShareLink = { _, shareID in
                shares.withValue { $0.removeAll { $0.id == shareID } }
            }
        }
    }
#endif
