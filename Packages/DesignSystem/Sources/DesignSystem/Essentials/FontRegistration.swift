import CoreText
import Foundation

public enum DesignSystemFonts {
    /// Registers the Outfit variable font from this package's resource bundle with the
    /// system font manager. Call once at app launch, before any `Font.custom("Outfit", ...)`
    /// is used — package-bundled fonts aren't picked up by Info.plist `UIAppFonts`, which
    /// only sees fonts in the main app bundle, so this has to happen at runtime instead.
    public static func registerAll() {
        guard let url = Bundle.module.url(
            forResource: "Figtree-VariableFont_wght",
            withExtension: "ttf",
            subdirectory: "Fonts"
        ) else {
            return
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
}
