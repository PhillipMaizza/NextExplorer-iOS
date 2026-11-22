#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let chromeButtonOpacity: Double = 0.055
        static let chromeHoverOpacity: Double = 0.045
        static let hairlineShadowOpacity: Double = 0.06
        static let tertiaryOpacity: Double = 0.6
    }

    enum MacOpacity {
        static let disabled: Double = 0.4
    }

    public extension Color {
        static let macChrome = Color("MacChrome", bundle: .module)
        static let macCard = Color("MacCard", bundle: .module)
        static let macSelection = Color("MacSelection", bundle: .module)
        static let macRow = Color("MacRow", bundle: .module)
        static let macLine = Color("MacLine", bundle: .module)
        static let macSegment = Color("MacSegment", bundle: .module)
        static let macField = Color("MacField", bundle: .module)
        static let macChromeText = Color("MacChromeText", bundle: .module)
        static let macChromeSecondary = Color("MacChromeSecondary", bundle: .module)
        static let macTagGreen = Color("MacTagGreen", bundle: .module)
        static let macTagGreenFill = Color("MacTagGreenFill", bundle: .module)
        static let macTagRed = Color("MacTagRed", bundle: .module)
        static let macTagRedFill = Color("MacTagRedFill", bundle: .module)
        static let macTagAmber = Color("MacTagAmber", bundle: .module)
        static let macTagAmberFill = Color("MacTagAmberFill", bundle: .module)
        static let macTagGray = Color("MacTagGray", bundle: .module)
        static let macTagGrayFill = Color("MacTagGrayFill", bundle: .module)
        static let macChromeButton = Color.macChromeText.opacity(Constants.chromeButtonOpacity)
        static let macChromeHover = Color.macChromeText.opacity(Constants.chromeHoverOpacity)
        static let macChromeTertiary = Color.macChromeSecondary.opacity(Constants.tertiaryOpacity)
        static let macCardShadow = Color.black.opacity(Constants.hairlineShadowOpacity)
    }
#endif
