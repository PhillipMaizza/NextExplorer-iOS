import SwiftUI

public enum DSAlertIcon: Sendable {
    case delete
    case warning
    case signOut
    case shield
    case drive
    case unfavorite
    case shareLink
    case restore
    case rename
    case download
    case offline
    case lock
    case camera

    public var image: Image {
        #if os(macOS)
            switch self {
            case .delete: IconKit.macTrash
            case .warning: IconKit.macWarning
            case .signOut: IconKit.macSignOut
            case .shield: IconKit.macShield
            case .drive: IconKit.macDrive
            case .unfavorite: IconKit.macStarSlash
            case .shareLink: IconKit.macLink
            case .restore: IconKit.macRestore
            case .rename: IconKit.macPencil
            case .download: IconKit.macDownload
            case .offline: IconKit.macOffline
            case .lock: IconKit.macLock
            case .camera: IconKit.macCamera
            }
        #else
            switch self {
            case .delete: IconKit.delete
            case .warning: IconKit.warning
            case .signOut: IconKit.signOut
            case .shield: IconKit.shield
            case .drive: IconKit.drive
            case .unfavorite: IconKit.unfavorite
            case .shareLink: IconKit.shareLink
            case .restore: IconKit.restore
            case .rename: IconKit.rename
            case .download: IconKit.menuDownload
            case .offline: IconKit.availableOffline
            case .lock: IconKit.lock
            case .camera: IconKit.camera
            }
        #endif
    }
}
