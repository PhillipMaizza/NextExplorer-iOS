import Foundation
import Localization
import ShareUploads
import UniformTypeIdentifiers

/// What the extension needs to know about a shared item beyond staging it (that is
/// `SharedItemLoader.stageAll`, which reports progress and stops the copy on cancellation).
enum ProviderStager {
    /// A Live Photo stands for a still and its motion video.
    static func isLivePhoto(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.compactMap(UTType.init).contains { $0.conforms(to: .livePhoto) }
    }

    /// The name shown for an item that failed: the provider's own, else its position.
    static func displayName(of provider: NSItemProvider, index: Int) -> String {
        guard let name = provider.suggestedName, !name.isEmpty else {
            return L10n.ShareUpload.fallbackItemName(index + 1)
        }
        return name
    }

    /// `NSItemProvider` wraps what went wrong in its own error and keeps the real one underneath,
    /// so the cause is read from the innermost error that says something.
    static func cause(of error: any Error) -> ItemFailureCause {
        if let shareError = error as? ShareUploadError, shareError == .isFolder {
            return .folder
        }
        if ShareUploadError.isOutOfSpace(error) {
            return .notEnoughSpace
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: nsError.code) {
            case .fileReadNoSuchFile, .fileNoSuchFile, .fileReadNoPermission, .fileReadUnknown, .fileReadCorruptFile:
                return .cannotRead
            default: break
            }
        }
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else { return .other }
        return cause(of: underlying)
    }
}
