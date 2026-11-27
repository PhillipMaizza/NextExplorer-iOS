import CoreModels
import FilesClient
import Foundation

enum ZoneOwners {
    static func names(_ filesClient: FilesClient, _ serverURL: URL) async -> [String: String] {
        let users = await (try? filesClient.listUsers(serverURL)) ?? []
        return Dictionary(users.map { ($0.id, $0.displayLabel) }) { first, _ in first }
    }

    static func named(_ zone: VersionedZone?, _ names: [String: String]) -> VersionedZone? {
        guard var zone, zone.kind == .personal else { return zone }
        zone.ownerName = names[zone.name]
        return zone
    }
}
