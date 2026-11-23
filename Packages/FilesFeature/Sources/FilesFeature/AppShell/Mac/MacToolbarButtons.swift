#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let iconSize: CGFloat = 18
        static let buttonSize: CGFloat = .size40
    }

    enum MacToolbarMetrics {
        static let gap: CGFloat = 10
    }

    struct MacToolbarCircleButtonStyle: ButtonStyle {
        var tint: Color = .macChromeText

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(tint)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(Circle().fill(configuration.isPressed ? Color.macChromeHover : Color.macChromeButton))
                .contentShape(Circle())
                .macDisabledDim()
        }
    }

    extension ButtonStyle where Self == MacToolbarCircleButtonStyle {
        static var macToolbarCircle: MacToolbarCircleButtonStyle {
            MacToolbarCircleButtonStyle()
        }

        static var macToolbarCircleAccent: MacToolbarCircleButtonStyle {
            MacToolbarCircleButtonStyle(tint: .accentText)
        }
    }

    extension ToolbarContent {
        @ToolbarContentBuilder
        func macPlainToolbarItem() -> some ToolbarContent {
            if #available(macOS 26.0, *) {
                sharedBackgroundVisibility(.hidden)
            } else {
                self
            }
        }
    }

    extension Image {
        func macToolbarGlyph() -> some View {
            resizable()
                .scaledToFit()
                .frame(width: Constants.iconSize, height: Constants.iconSize)
        }
    }
#endif
