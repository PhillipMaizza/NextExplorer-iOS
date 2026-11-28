import DesignSystem
import SwiftUI

enum MenuIcon {
    case open(isDirectory: Bool)
    case openLocation
    case openWith
    case viewAsText
    case print
    case getInfo
    case permissions
    case openInBrowser
    case refresh
    case copy
    case duplicate
    case cut
    case move
    case copyTo
    case paste
    case rename
    case extract
    case compress
    case download
    case keepOffline
    case systemShare
    case shareLink
    case directLink
    case favorite(isOn: Bool)
    case unfavorite
    case delete
    case restore
    case restoreTo
    case newFolder
    case newFile
    case upload
    case versions

    #if os(macOS)
        var panelImage: Image {
            switch self {
            case .open, .openLocation: IconKit.macOpen
            case .openWith: IconKit.macOpenWith
            case .viewAsText: IconKit.macDocument
            case .print: IconKit.macPrint
            case .getInfo: IconKit.macInfo
            case .permissions: IconKit.macLock
            case .openInBrowser: IconKit.macGlobe
            case .refresh: IconKit.macRefresh
            case .copy, .copyTo: IconKit.macCopy
            case .duplicate: IconKit.macDuplicate
            case .cut: IconKit.macCut
            case .move: IconKit.macMove
            case .paste: IconKit.macPaste
            case .rename: IconKit.macPencil
            case .extract: IconKit.macExtract
            case .compress: IconKit.macArchive
            case .download: IconKit.macDownload
            case .keepOffline: IconKit.macOffline
            case .systemShare: IconKit.macShare
            case .shareLink, .directLink: IconKit.macLink
            case let .favorite(isOn): isOn ? IconKit.macStarFill : IconKit.macStar
            case .unfavorite: IconKit.macStarFill
            case .delete: IconKit.macTrash
            case .restore: IconKit.macRestore
            case .restoreTo: IconKit.macFolder
            case .newFolder: IconKit.macNewFolder
            case .newFile: IconKit.macNewFile
            case .upload: IconKit.macUpload
            case .versions: IconKit.macClock
            }
        }
    #endif

    var image: Image {
        switch self {
        case let .open(isDirectory): isDirectory ? IconKit.folder : IconKit.document
        case .openLocation, .newFolder: IconKit.folder
        case .openWith: IconKit.openInApp
        case .viewAsText: IconKit.document
        case .print: IconKit.print
        case .getInfo: IconKit.info
        case .permissions: IconKit.lock
        case .openInBrowser: IconKit.web
        case .refresh: IconKit.retry
        case .copy: IconKit.copy
        case .duplicate, .copyTo: IconKit.duplicate
        case .cut: IconKit.cut
        case .move: IconKit.move
        case .systemShare: IconKit.share
        case .paste: IconKit.paste
        case .rename: IconKit.rename
        case .extract: IconKit.extract
        case .compress: IconKit.archiveDocument
        case .download: IconKit.download
        case .keepOffline: IconKit.availableOffline
        case .shareLink: IconKit.shareLink
        case .directLink: IconKit.link
        case let .favorite(isOn): isOn ? IconKit.starFill : IconKit.star
        case .unfavorite: IconKit.unfavorite
        case .delete: IconKit.delete
        case .restore: IconKit.restore
        case .restoreTo: IconKit.restoreTo
        case .newFile: IconKit.newFile
        case .upload: IconKit.upload
        case .versions: IconKit.time
        }
    }
}
