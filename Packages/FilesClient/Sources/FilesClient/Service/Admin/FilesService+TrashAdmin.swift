import CoreModels
import Foundation
import NetworkClient

/// The administrator's side of the trash, `backend/src/routes/trash.js`: what each volume holds,
/// whether its books and its disk agree, and running the maintenance pass now.
extension FilesService {
    private struct ZonesEnvelope: Decodable {
        let zones: [TrashZone]
    }

    private struct VerificationEnvelope: Decodable {
        let zones: [TrashVerification]
    }

    func fetchTrashZones(serverURL: URL) async throws -> [TrashZone] {
        let request = Self.makeRequest(url: serverURL.appendingPathComponent(APIPath.trashZones), method: .get)
        return try await sendReportingMessage(request, decoding: ZonesEnvelope.self).zones
    }

    func verifyTrash(serverURL: URL) async throws -> [TrashVerification] {
        let request = Self.makeRequest(
            url: serverURL.appendingPathComponent(APIPath.trashVerify),
            method: .post,
            isMutation: true
        )
        return try await sendReportingMessage(request, decoding: VerificationEnvelope.self).zones
    }

    func runTrashMaintenance(serverURL: URL) async throws {
        let request = Self.makeRequest(
            url: serverURL.appendingPathComponent(APIPath.trashMaintenance),
            method: .post,
            isMutation: true
        )
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }
}
