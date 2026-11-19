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
            client.mySharedLinks = { _ in shares.value }
            client.updateShareLink = { _, shareID, request in
                try shares.withValue { list in
                    guard let index = list.firstIndex(where: { $0.id == shareID }) else {
                        throw FilesClientError.server(statusCode: 404)
                    }
                    list[index] = list[index].applying(request, at: Date())
                    return list[index]
                }
            }
            client.deleteShareLink = { _, shareID in
                shares.withValue { $0.removeAll { $0.id == shareID } }
            }
        }
    }
#endif
