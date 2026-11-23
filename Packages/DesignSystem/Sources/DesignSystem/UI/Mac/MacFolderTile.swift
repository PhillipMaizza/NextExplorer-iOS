#if os(macOS)
    import SwiftUI

    public struct MacFolderTile: View {
        private enum Metrics {
            static let cornerFraction: CGFloat = 0.28
            static let glyphFraction: CGFloat = 0.52
            static let fillOpacity: Double = 0.17
        }

        let size: CGFloat
        var glyph = IconKit.folderFill
        var tint = Color.accent

        public init(size: CGFloat, glyph: Image = IconKit.folderFill, tint: Color = .accent) {
            self.size = size
            self.glyph = glyph
            self.tint = tint
        }

        public var body: some View {
            RoundedRectangle(cornerRadius: size * Metrics.cornerFraction, style: .continuous)
                .fill(tint.opacity(Metrics.fillOpacity))
                .overlay {
                    glyph
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * Metrics.glyphFraction, height: size * Metrics.glyphFraction)
                        .foregroundStyle(tint)
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    #Preview("Folder tiles") {
        HStack(spacing: .space16) {
            MacFolderTile(size: .size24)
            MacFolderTile(size: .size40, glyph: IconKit.person)
            MacFolderTile(size: .size40, glyph: IconKit.starFill, tint: .red)
        }
        .padding()
        .background(Color.macCard)
    }
#endif
