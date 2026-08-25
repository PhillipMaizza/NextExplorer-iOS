import CoreText
import Foundation
#if canImport(UIKit)
import UIKit
#endif

private enum Constants {
    static let navTitleSize: CGFloat = 17
    static let navTitleWeight: CGFloat = 800
    static let largeTitleSize: CGFloat = 34
    static let largeTitleWeight: CGFloat = 800
    static let tabItemSize: CGFloat = 12
    static let tabItemNormalWeight: CGFloat = 400
    static let tabItemSelectedWeight: CGFloat = 600
    /// UIKit variation-axis fallback threshold: below this, `weightedFont` falls back to
    /// `.systemFont(weight: .regular)` rather than `.semibold`.
    static let systemFontSemiboldThreshold: CGFloat = 600
}

public enum DesignSystemFonts {
    private static let familyName = "Figtree"

    /// Registers the Figtree variable font from this package's resource bundle with the
    /// system font manager. Call once at app launch, before any `Font.custom("Figtree", ...)`
    /// is used: package-bundled fonts aren't picked up by Info.plist `UIAppFonts`, which
    /// only sees fonts in the main app bundle, so this has to happen at runtime instead.
    ///
    /// `NetxExplorerApp.init()` calls this eagerly, and `Typography.TextType.fontsRegistered`
    /// also calls it lazily on first use (for Xcode previews, which never run `init()`) — in a
    /// real app run both fire, possibly concurrently. Backed by a `static let` rather than a
    /// hand-rolled bool guard so the once-only registration is the compiler-guaranteed atomic
    /// lazy-init Swift already provides, instead of an unsynchronized flag.
    public static func registerAll() {
        _ = registerOnce
    }

    private static let registerOnce: Void = {
        guard let url = Bundle.module.url(
            forResource: "Figtree-VariableFont_wght",
            withExtension: "ttf",
            subdirectory: "Fonts"
        ) else {
            return
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }()

    #if canImport(UIKit)
    /// Applies Figtree to the UIKit-rendered chrome SwiftUI's `.font()` modifier can't
    /// reach (navigation bar titles and tab bar item labels) via the shared appearance
    /// proxies. Call once at launch, after `registerAll()`. Only text attributes are set;
    /// background/translucency are left at their defaults so this doesn't fight the
    /// gradient wash the rest of the app draws behind system chrome.
    @MainActor
    public static func applyGlobalAppearance() {
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.titleTextAttributes = [.font: weightedFont(size: Constants.navTitleSize, weight: Constants.navTitleWeight)]
        navBarAppearance.largeTitleTextAttributes = [.font: weightedFont(size: Constants.largeTitleSize, weight: Constants.largeTitleWeight)]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance

        let tabItemAppearance = UITabBarItemAppearance()
        tabItemAppearance.normal.titleTextAttributes = [.font: weightedFont(size: Constants.tabItemSize, weight: Constants.tabItemNormalWeight)]
        tabItemAppearance.selected.titleTextAttributes = [.font: weightedFont(size: Constants.tabItemSize, weight: Constants.tabItemSelectedWeight)]
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.stackedLayoutAppearance = tabItemAppearance
        tabBarAppearance.inlineLayoutAppearance = tabItemAppearance
        tabBarAppearance.compactInlineLayoutAppearance = tabItemAppearance
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    /// Figtree is a variable font registered as one family at its default (Light)
    /// instance. UIKit has no `.fontWeight()`-style modifier, so a specific weight has
    /// to be dialed in directly on the `wght` variation axis.
    private static func weightedFont(size: CGFloat, weight: CGFloat) -> UIFont {
        guard UIFont(name: familyName, size: size) != nil else {
            return .systemFont(ofSize: size, weight: weight >= Constants.systemFontSemiboldThreshold ? .semibold : .regular)
        }

        let kWeightAxisIdentifier: FourCharCode = 0x77676874
        let variation: [CFNumber: CFNumber] = [
            (kWeightAxisIdentifier as CFNumber): (weight as CFNumber)
        ]

        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: familyName as CFString,
            kCTFontVariationAttribute: variation
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return ctFont as UIFont
    }
    #else
    public static func applyGlobalAppearance() {}
    #endif
}
