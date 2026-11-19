#if DEBUG
    import CoreModels
    import FilesClient
    import Foundation

    extension UITestSupport {
        /// Replaces the listing routes of `areas` so they come back empty.
        static func empty(_ areas: Set<UITestArea>, in client: inout FilesClient) {
            for area in areas {
                switch area {
                case .browse:
                    client.browse = { _, path in BrowseResult(items: [], access: fullAccess, path: path) }
                case .search:
                    client.search = { _, _, _, _ in [] }
                case .favorites:
                    client.favorites = { _ in [] }
                case .shares:
                    client.mySharedLinks = { _ in [] }
                    client.sharedWithMeLinks = { _ in [] }
                case .trash:
                    client.fetchTrash = { _ in TrashListing(
                        isEnabled: true,
                        retentionDays: trashRetentionDays,
                        items: []
                    ) }
                case .users:
                    client.listUsers = { _ in [user] }
                case .activity:
                    client.fetchActivity = { _, _, _ in ActivityPage(isEnabled: true) }
                case .versions:
                    client.fetchVersionedFiles = { _, _, _, _ in VersionedFilesPage() }
                case .accessRules:
                    let base = client.fetchSystemSettings
                    client.fetchSystemSettings = { serverURL in
                        var settings = try await base(serverURL)
                        settings.accessRules = []
                        return settings
                    }
                case .apiTokens:
                    client.fetchAPITokens = { _ in [] }
                }
            }
        }

        /// Replaces the listing routes of `areas` so they fail as an unreachable server does.
        static func fail(_ areas: Set<UITestArea>, in client: inout FilesClient) {
            let failure = FilesClientError.network(injectedFailure)
            for area in areas {
                switch area {
                case .browse:
                    client.browse = { _, _ in throw failure }
                case .search:
                    client.search = { _, _, _, _ in throw failure }
                case .favorites:
                    client.favorites = { _ in throw failure }
                case .shares:
                    client.mySharedLinks = { _ in throw failure }
                    client.sharedWithMeLinks = { _ in throw failure }
                case .trash:
                    client.fetchTrash = { _ in throw failure }
                case .users:
                    client.listUsers = { _ in throw failure }
                case .activity:
                    client.fetchActivity = { _, _, _ in throw failure }
                case .versions:
                    client.fetchVersionedFiles = { _, _, _, _ in throw failure }
                case .accessRules:
                    client.fetchSystemSettings = { _ in throw failure }
                case .apiTokens:
                    client.fetchAPITokens = { _ in throw failure }
                }
            }
        }
    }
#endif
