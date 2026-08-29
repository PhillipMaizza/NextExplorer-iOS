import Foundation

/// Response from `POST /api/files/delete-impact`, confirmed against
/// `backend/src/services/fileTransferService.js`'s `getDeleteImpact`: the share links
/// anchored to the items about to be deleted. `deleteItems` on the server removes those
/// links as part of the delete, so this is a pre-delete warning, never a blocker. Only the
/// count is modelled — the server also returns the share rows, but the confirmation UI, like
/// the web client's, only shows how many links will break.
public struct DeleteImpact: Decodable, Equatable, Sendable {
    public let shareCount: Int

    public init(shareCount: Int) {
        self.shareCount = shareCount
    }
}
