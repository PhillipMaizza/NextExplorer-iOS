import CoreModels
import Foundation
import Localization

/// The one file size formatter every row, table, sheet and Settings pane shares, so sizes read
/// the same everywhere and the formatter is built once.
@MainActor
enum FileSizeFormat {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }

    /// A file's size, or a folder's indexed size; a folder the server has not counted shows a placeholder.
    static func string(for item: FileItem, folderSize: Int64?) -> String {
        guard item.isDirectory else { return string(item.size) }
        return folderSize.map { string($0) } ?? L10n.Browse.noValue
    }
}
