import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let chipCornerFraction: CGFloat = 0.28
    static let chipGlyphFraction: CGFloat = 0.52
    static let lightChipOpacity: Double = 0.16
    static let darkChipOpacity: Double = 0.24
    /// Colours for kinds with none of their own, kept clear of the photo, video, audio and archive colours.
    static let palette: [UInt32] = [0x14B8A6, 0xF43F5E, 0x0EA5E9, 0x84CC16, 0x6366F1, 0xEC4899]
    static let hashMultiplier = 31
    static let minLuminance: Double = 0.08
    static let redWeight: Double = 0.2126
    static let greenWeight: Double = 0.7152
    static let blueWeight: Double = 0.0722
    static let javaArchiveKinds: Set<String> = ["jar", "war", "ear"]
    static let installerKinds: Set<String> = ["exe", "msi", "apk", "dmg", "pkg", "deb", "rpm", "ipa", "appimage"]
    static let databaseKinds: Set<String> = ["db", "sqlite", "sqlite3", "sql"]
    static let spreadsheetKinds: Set<String> = ["xls", "xlsx", "csv", "gsheet", "numbers", "ods"]
    static let keyKinds: Set<String> = ["key", "pem", "crt", "cer", "pub", "p12", "pfx", "gpg", "asc"]
    static let documentKinds: Set<String> = [
        "doc", "docx", "rtf", "pdf", "txt", "md", "markdown", "pages", "odt", "gdoc", "log",
    ]
}

/// A file's type icon, the same everywhere a file is drawn without a picture of its own (list
/// rows, grid wells, the preview's "cannot open" screen, Mac tables): a soft rounded chip tinted
/// with the kind's colour holding the kind's glyph.
struct FileTypeIcon: View {
    let kind: String
    @Environment(\.colorScheme) private var colorScheme

    static let cornerFraction = Constants.chipCornerFraction

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let color = Self.color(forKind: kind)
            RoundedRectangle(cornerRadius: side * Constants.chipCornerFraction, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? Constants.darkChipOpacity : Constants.lightChipOpacity))
                .frame(width: side, height: side)
                .overlay {
                    (Self.kindGlyph(forKind: kind) ?? IconKit.document)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(color)
                        .frame(width: side * Constants.chipGlyphFraction, height: side * Constants.chipGlyphFraction)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The kind's own colour, else a steady one picked from its extension, so every `.exe` matches.
    /// A file with no extension stays neutral.
    static func color(forKind kind: String) -> Color {
        guard !kind.isEmpty, kind != FileItem.unknownKind else { return .secondaryDS }
        if let own = tint(forKind: kind), isReadable(own) {
            return own
        }
        return Color(hex: Constants.palette[paletteIndex(forKind: kind)])
    }

    /// A stable index: `hashValue` changes on every launch, so the letters are summed by hand.
    nonisolated static func paletteIndex(forKind kind: String) -> Int {
        let hash = kind.lowercased().unicodeScalars.reduce(0) { $0 &* Constants.hashMultiplier &+ Int($1.value) }
        return abs(hash % Constants.palette.count)
    }

    /// A kind's own colour darker than the floor (an installer's near black) cannot be read on a surface.
    private static func isReadable(_ color: Color) -> Bool {
        let resolved = color.resolve(in: EnvironmentValues())
        let luminance = Constants.redWeight * Double(resolved.linearRed)
            + Constants.greenWeight * Double(resolved.linearGreen)
            + Constants.blueWeight * Double(resolved.linearBlue)
        return luminance >= Constants.minLuminance
    }

    /// The colour a kind is known by, `nil` for kinds with none of their own.
    static func tint(forKind kind: String) -> Color? {
        if FileItem.isImageKind(kind) || FileItem.isRawImageKind(kind) {
            Color(hex: 0x10B981)
        } else if FileItem.isVideoKind(kind) {
            Color(hex: 0x7C3AED)
        } else if FileItem.isAudioKind(kind) {
            Color(hex: 0x06B6D4)
        } else if FileItem.isArchiveKind(kind) || Constants.javaArchiveKinds.contains(kind.lowercased()) {
            Color(hex: 0xF59E0B)
        } else {
            FileItem.kindColor(forKind: kind)
        }
    }

    /// The glyph a type icon holds: archives, installers, code, fonts, databases, sheets, keys and
    /// media each get their own; anything else takes the plain document glyph.
    static func kindGlyph(forKind kind: String) -> Image? {
        let kind = kind.lowercased()
        if FileItem.isArchiveKind(kind) || Constants.javaArchiveKinds.contains(kind) {
            return IconKit.kindArchive
        }
        if FileItem.isImageKind(kind) || FileItem.isRawImageKind(kind) {
            return IconKit.photo
        }
        if FileItem.isVideoKind(kind) {
            return IconKit.film
        }
        if FileItem.isAudioKind(kind) {
            return IconKit.music
        }
        if Constants.installerKinds.contains(kind) {
            return IconKit.kindInstaller
        }
        if FileItem.fontExtensions.contains(kind) {
            return IconKit.kindFont
        }
        if Constants.databaseKinds.contains(kind) {
            return IconKit.kindDatabase
        }
        if Constants.spreadsheetKinds.contains(kind) {
            return IconKit.table
        }
        if Constants.keyKinds.contains(kind) {
            return IconKit.key
        }
        if !Constants.documentKinds.contains(kind), TextSnippet.isTextKind(kind) {
            return IconKit.kindCode
        }
        return nil
    }
}

#Preview("Media kinds") {
    HStack(spacing: .space16) {
        FileTypeIcon(kind: "jpg")
        FileTypeIcon(kind: "mp4")
        FileTypeIcon(kind: "mp3")
        FileTypeIcon(kind: "zip")
        FileTypeIcon(kind: "pdf")
    }
    .frame(height: .iconLarge)
    .padding(.space16)
}

#Preview("Badged extensions") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: .space16) {
        ForEach(
            [
                "doc",
                "xls",
                "ppt",
                "csv",
                "txt",
                "md",
                "html",
                "css",
                "js",
                "ts",
                "json",
                "yaml",
                "py",
                "swift",
                "go",
                "rs",
            ],
            id: \.self
        ) { kind in
            FileTypeIcon(kind: kind)
        }
    }
    .frame(height: .iconLarge)
    .padding(.space16)
}

#Preview("No colour of their own, then no extension") {
    HStack(spacing: .space16) {
        FileTypeIcon(kind: "jar")
        FileTypeIcon(kind: "exe")
        FileTypeIcon(kind: "docx")
        FileTypeIcon(kind: "xyz123")
        FileTypeIcon(kind: FileItem.unknownKind)
    }
    .frame(height: .iconLarge)
    .padding(.space16)
}

#Preview("Dark") {
    HStack(spacing: .space16) {
        FileTypeIcon(kind: "jar")
        FileTypeIcon(kind: "exe")
        FileTypeIcon(kind: "pdf")
        FileTypeIcon(kind: "mp3")
    }
    .frame(height: .iconLarge)
    .padding(.space16)
    .background(Color.backgroundPrimary)
    .preferredColorScheme(.dark)
}
