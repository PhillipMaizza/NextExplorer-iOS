import Foundation

/// One file the user picked to upload, already copied to a temp location the app owns (the
/// document picker's security-scoped URLs and Photos data don't outlive the picker callback).
/// Carries the destination folder it was requested from, so uploads started in one folder
/// finish there even after the user navigates away.
public struct PendingUpload: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let fileURL: URL
    public let fileName: String
    public let destination: String

    public init(id: UUID = UUID(), fileURL: URL, fileName: String, destination: String) {
        self.id = id
        self.fileURL = fileURL
        self.fileName = fileName
        self.destination = destination
    }
}
