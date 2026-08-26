import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let iconFrame: CGFloat = .iconMedium
    static let chevronSize: CGFloat = .iconXSmall
    static let fullOpacity: Double = 1.0
    static let halfOpacity: Double = 0.5
}

struct FileRowView: View {
    let name: String
    let isDirectory: Bool
    let dateModified: Date?
    let size: Int64?
    let customSubtitle: String?
    let isFavorite: Bool
    /// Read live so an already-visible row updates immediately when the user changes the
    /// date format in Settings, rather than only on the next fetch.
    @AppStorage("dateDisplayFormat") private var dateFormatRaw = DateDisplayFormat.system.rawValue

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    init(name: String, isDirectory: Bool, subtitle: String? = nil, isFavorite: Bool = false) {
        self.name = name
        self.isDirectory = isDirectory
        self.dateModified = nil
        self.size = nil
        self.customSubtitle = subtitle
        self.isFavorite = isFavorite
    }

    init(item: FileItem, isFavorite: Bool = false) {
        self.name = item.name
        self.isDirectory = item.isDirectory
        self.dateModified = item.dateModified
        self.size = item.isDirectory ? nil : item.size
        self.customSubtitle = nil
        self.isFavorite = isFavorite
    }

    private var dateFormat: DateDisplayFormat { DateDisplayFormat(rawValue: dateFormatRaw) ?? .system }

    private var subtitle: String? {
        if let customSubtitle { return customSubtitle }
        guard let dateModified else { return nil }
        let dateText = dateFormat.string(from: dateModified)
        guard let size else { return dateText }
        return "\(Self.byteFormatter.string(fromByteCount: size)) • \(dateText)"
    }

    private var isHidden: Bool { isHiddenFileName(name) }

    var body: some View {
        HStack(spacing: .space12) {
            (isDirectory ? IconKit.folderFill : IconKit.document)
                .resizable()
                .foregroundStyle(isDirectory ? Color.accent : Color.secondaryDS)
                .frame(width: Constants.iconFrame, height: Constants.iconFrame)
                .opacity(isHidden ? Constants.halfOpacity : Constants.fullOpacity)

            VStack(alignment: .leading, spacing: .space2) {
                Text(name)
                    .type(.body2(.semibold), style: isHidden ? .tertiary : .primary(for: .label))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .type(.body3(.regular), style: isHidden ? .tertiary : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isFavorite {
                IconKit.starFill
                    .resizable()
                    .foregroundStyle(Color.accent)
                    .frame(width: .iconSmall, height: .iconSmall)
            }

            if isDirectory {
                IconKit.chevronRight
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.chevronSize, height: Constants.chevronSize)
            }
        }
        .padding(.vertical, .space4)
        .contentShape(Rectangle())
    }
}

/// Dotfile convention (`.something`): the server's own default `hiddenFiles` pattern
/// (`backend/src/config/index.js`, confirmed via `hidden-files-config.test.js`) before
/// an admin adds extra `HIDDEN_FILE_PATTERNS`, which this client has no way to know about.
func isHiddenFileName(_ name: String) -> Bool {
    name.hasPrefix(".")
}


#Preview {
    VStack(spacing: .space16) {
        FileRowView(name: "Folder",
                    isDirectory: true,
                    subtitle: nil)
        FileRowView(name: "Folder",
                    isDirectory: true,
                    subtitle: "Aug 20, 2026")
        FileRowView(name: "Favorite Folder",
                    isDirectory: true,
                    subtitle: "Aug 20, 2026",
                    isFavorite: true)
        FileRowView(name: ".hidden",
                    isDirectory: true,
                    subtitle: nil)
        FileRowView(name: "File",
                    isDirectory: false,
                    subtitle: nil)
        FileRowView(name: ".hidden",
                    isDirectory: false,
                    subtitle: nil)
        FileRowView(name: "File",
                    isDirectory: false,
                    subtitle: "18kb")
        FileRowView(name: "Favorite File",
                    isDirectory: false,
                    subtitle: "18kb",
                    isFavorite: true)
        FileRowView(name: ".hidden",
                    isDirectory: false,
                    subtitle: "18kb")

    }
    .padding(.space16)
}
