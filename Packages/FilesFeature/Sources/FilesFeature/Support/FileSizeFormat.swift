import Foundation

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
}
