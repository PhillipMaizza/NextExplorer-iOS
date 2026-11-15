import CoreModels
import FilesClient
import Foundation

/// Where a gallery photo is read from. Offline it never starts the progressive stream, which would
/// sit until its request timed out and leave the page blank: it decodes the copy kept on the device,
/// or goes straight to the preview file, which serves the cached or pinned copy.
enum GalleryImageSource: Equatable {
    case local(URL)
    case stream(URL)
    case download

    /// `verifiedCopy` is the pinned copy whose date and size match `item`; `anyPinnedCopy` is a pinned
    /// copy of the same path whatever its date and size, for a file opened from a listing whose
    /// metadata no longer matches what was kept.
    static func resolve(
        item: FileItem,
        serverURL: URL,
        verifiedCopy: URL?,
        anyPinnedCopy: URL?,
        isOnline: Bool
    ) -> GalleryImageSource {
        if let verifiedCopy {
            return .local(verifiedCopy)
        }
        guard isOnline else {
            return anyPinnedCopy.map(GalleryImageSource.local) ?? .download
        }
        return FilesClient.previewURL(serverURL: serverURL, item: item).map(GalleryImageSource.stream) ?? .download
    }
}
