import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let foldFraction: CGFloat = 0.32
    static let cornerRadius: CGFloat = .size4
    static let pageStrokeWidth: CGFloat = 1
    static let glyphIconFraction: CGFloat = 0.5
    static let badgeHeightFraction: CGFloat = 0.4
    static let badgeCornerRadius: CGFloat = .size2
    static let badgeHorizontalInset: CGFloat = 0.05
    static let badgeFontMinScale: CGFloat = 0.5
    static let badgeMinFontSize: CGFloat = 6
    static let plainLabelMaxLength = 5
    /// Faint text lines on a big empty page, as shares of its width, so it reads as a written sheet.
    static let lineWidths: [CGFloat] = [0.6, 0.72, 0.5, 0.66]
    static let lineHeightShare: CGFloat = 0.04
    static let lineSpacingShare: CGFloat = 0.06
    static let lineInsetShare: CGFloat = 0.14
    static let linesTopShare: CGFloat = 0.38
    static let lineOpacity: Double = 0.5
    static let pageTintOpacity: Double = 0.14
    static let kindGlyphShare: CGFloat = 0.34
    static let kindGlyphCenterShare: CGFloat = 0.42
    static let javaArchiveKinds: Set<String> = ["jar", "war", "ear"]
    static let installerKinds: Set<String> = ["exe", "msi", "apk", "dmg", "pkg", "deb", "rpm", "ipa", "appimage"]
    static let fontKinds: Set<String> = ["ttf", "otf", "woff", "woff2"]
    static let databaseKinds: Set<String> = ["db", "sqlite", "sqlite3", "sql"]
    static let spreadsheetKinds: Set<String> = ["xls", "xlsx", "csv", "gsheet", "numbers", "ods"]
    static let keyKinds: Set<String> = ["key", "pem", "crt", "cer", "pub", "p12", "pfx", "gpg", "asc"]
    static let documentKinds: Set<String> = [
        "doc", "docx", "rtf", "pdf", "txt", "md", "markdown", "pages", "odt", "gdoc", "log",
    ]
}

/// A page silhouette with a folded top right corner: the same base shape the web app's
/// `FileBadgeIcon.vue`/`txt-icon.vue`/etc. all share, just as a native `Shape` instead of a
/// literal SVG path.
struct FilePageShape: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = min(rect.width, rect.height) * Constants.foldFraction
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + Constants.cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - Constants.cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - Constants.cornerRadius, y: rect.maxY - Constants.cornerRadius),
            radius: Constants.cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + Constants.cornerRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + Constants.cornerRadius, y: rect.maxY - Constants.cornerRadius),
            radius: Constants.cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + Constants.cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + Constants.cornerRadius, y: rect.minY + Constants.cornerRadius),
            radius: Constants.cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// A real per file type icon: a page silhouette with a bottom banner showing the extension
/// itself, so every kind reads its own format. Kinds with no dedicated colour get a neutral
/// banner; a missing or overlong extension falls back to a plain page.
struct FileTypeIcon: View {
    let kind: String
    /// The banner's share of the page's height; a page drawn big takes `FileTypeBanner.slimHeightFraction`.
    var bannerHeightFraction: CGFloat = Constants.badgeHeightFraction

    /// A page drawn big (a grid well, with a slim banner) has room to say what the file is; a row
    /// icon stays clean.
    private var isBig: Bool {
        bannerHeightFraction < Constants.badgeHeightFraction
    }

    var body: some View {
        FilePageShape()
            .fill(Color.backgroundSecondary)
            .overlay {
                if isBig, let tint = Self.bannerBadge(forKind: kind)?.background {
                    FilePageShape().fill(tint.opacity(Constants.pageTintOpacity))
                }
            }
            .overlay(FilePageShape().stroke(Color.tertiaryDS, lineWidth: Constants.pageStrokeWidth))
            .overlay(overlayContent)
    }

    @ViewBuilder
    private var overlayContent: some View {
        if Self.hasBanner(forKind: kind) {
            if isBig {
                if let glyph = Self.kindGlyph(forKind: kind) {
                    kindGlyphView(glyph)
                } else if Constants.documentKinds.contains(kind.lowercased()) {
                    placeholderLines
                }
            }
            FileTypeBanner(kind: kind, heightFraction: bannerHeightFraction)
        } else {
            glyph(IconKit.document, tint: Color.secondaryDS)
        }
    }

    /// The colour a kind is known by: its banner here, and the tint of a grid tile's picture well for
    /// files with no picture of their own. `nil` for kinds drawn as a plain page.
    static func tint(forKind kind: String) -> Color? {
        badge(forKind: kind)?.background
    }

    /// Whether a kind's page carries an extension banner, or stays a plain page.
    nonisolated static func hasBanner(forKind kind: String) -> Bool {
        bannerBadge(forKind: kind) != nil
    }

    fileprivate nonisolated static func bannerBadge(forKind kind: String) -> FileBadge? {
        badge(forKind: kind) ?? plainBadge(forKind: kind)
    }

    /// A kind with no colour of its own still reads its extension, on a neutral banner. Kinds too long
    /// for a banner, or none at all, keep the plain page.
    private nonisolated static func plainBadge(forKind kind: String) -> FileBadge? {
        guard kind != FileItem.unknownKind,
              (1 ... Constants.plainLabelMaxLength).contains(kind.count),
              kind.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        return FileBadge(label: kind.uppercased(), background: .secondaryDS, foreground: .backgroundPrimary)
    }

    private nonisolated static func badge(forKind kind: String) -> FileBadge? {
        if FileItem.isImageKind(kind) || FileItem.isRawImageKind(kind) {
            FileBadge(label: kind.uppercased(), background: Color(hex: 0x10B981), foreground: .white)
        } else if FileItem.isVideoKind(kind) {
            FileBadge(label: kind.uppercased(), background: Color(hex: 0x7C3AED), foreground: .white)
        } else if FileItem.isAudioKind(kind) {
            FileBadge(label: kind.uppercased(), background: Color(hex: 0x06B6D4), foreground: .white)
        } else if FileItem.isArchiveKind(kind) {
            FileBadge(label: kind.uppercased(), background: Color(hex: 0xF59E0B), foreground: .white)
        } else {
            FileItem.badge(forKind: kind)
        }
    }

    /// What a file is, for a big page: archives, installers, code, fonts, databases, sheets, keys and
    /// media each get their glyph. Documents get faint text lines instead; anything else stays plain.
    private static func kindGlyph(forKind kind: String) -> Image? {
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
        if Constants.fontKinds.contains(kind) {
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

    private func kindGlyphView(_ glyph: Image) -> some View {
        GeometryReader { proxy in
            let side = proxy.size.width * Constants.kindGlyphShare
            glyph
                .resizable()
                .scaledToFit()
                .foregroundStyle(Self.bannerBadge(forKind: kind)?.background ?? Color.secondaryDS)
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height * Constants.kindGlyphCenterShare)
        }
        .accessibilityHidden(true)
    }

    private var placeholderLines: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            VStack(alignment: .leading, spacing: width * Constants.lineSpacingShare) {
                ForEach(Constants.lineWidths, id: \.self) { share in
                    Capsule()
                        .fill(Color.tertiaryDS.opacity(Constants.lineOpacity))
                        .frame(width: width * share, height: width * Constants.lineHeightShare)
                }
            }
            .padding(.leading, width * Constants.lineInsetShare)
            .padding(.top, proxy.size.height * Constants.linesTopShare)
        }
        .accessibilityHidden(true)
    }

    private func glyph(_ image: Image, tint: Color) -> some View {
        GeometryReader { proxy in
            image
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(
                    width: proxy.size.width * Constants.glyphIconFraction,
                    height: proxy.size.height * Constants.glyphIconFraction
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// The extension banner along a page's foot, the same in a type icon and over a text file's own
/// lines. Draws nothing for a kind that keeps the plain page.
struct FileTypeBanner: View {
    /// The banner's share of a page drawn big (a grid well), so its label stays the size of a row icon's.
    static let slimHeightFraction: CGFloat = 0.2

    let kind: String
    /// The banner's share of the page's height.
    var heightFraction: CGFloat = Constants.badgeHeightFraction

    var body: some View {
        if let badge = FileTypeIcon.bannerBadge(forKind: kind) {
            badgeBanner(badge)
        }
    }

    private func badgeBanner(_ badge: FileBadge) -> some View {
        GeometryReader { proxy in
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: Constants.badgeCornerRadius)
                    .fill(badge.background)
                    .frame(height: proxy.size.height * heightFraction)
                    .overlay(
                        Text(badge.label)
                            .font(.system(
                                size: max(
                                    Constants.badgeMinFontSize,
                                    proxy.size.height * heightFraction * 0.62
                                ),
                                weight: .heavy
                            ))
                            .minimumScaleFactor(Constants.badgeFontMinScale)
                            .lineLimit(1)
                            .padding(.horizontal, proxy.size.width * Constants.badgeHorizontalInset)
                            .foregroundStyle(badge.foreground)
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
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

#Preview("Neutral banner, then a plain page") {
    HStack(spacing: .space16) {
        FileTypeIcon(kind: "jar", bannerHeightFraction: FileTypeBanner.slimHeightFraction)
        FileTypeIcon(kind: "exe", bannerHeightFraction: FileTypeBanner.slimHeightFraction)
        FileTypeIcon(kind: "docx", bannerHeightFraction: FileTypeBanner.slimHeightFraction)
        FileTypeIcon(kind: "jar")
        FileTypeIcon(kind: "xyz123")
        FileTypeIcon(kind: FileItem.unknownKind)
    }
    .frame(height: .iconLarge)
    .padding(.space16)
}
