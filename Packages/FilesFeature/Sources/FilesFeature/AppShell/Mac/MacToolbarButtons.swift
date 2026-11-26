#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let iconSize: CGFloat = .size18
        static let buttonSize: CGFloat = .size40
    }

    enum MacToolbarMetrics {
        static let gap: CGFloat = .space8
        static let appearScale: CGFloat = 0.6
    }

    struct MacToolbarCircleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(Color.macChromeText)
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
