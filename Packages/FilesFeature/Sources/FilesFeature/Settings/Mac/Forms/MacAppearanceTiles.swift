#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileHeight: CGFloat = .size96
        static let selectedBorder: CGFloat = .borderWidthStrong
        static let sidebarFraction: CGFloat = 0.3
        static let shape = RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
    }

    struct MacAppearanceTiles: View {
        @Binding var selection: AppearanceMode

        var body: some View {
            HStack(spacing: .space12) {
                ForEach(AppearanceMode.allCases) { mode in
                    tile(mode)
                }
            }
        }

        private func tile(_ mode: AppearanceMode) -> some View {
            let isSelected = selection == mode
            return Button { selection = mode } label: {
                VStack(spacing: .space8) {
                    swatch(mode)
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.tileHeight)
                        .clipShape(Metrics.shape)
                        .overlay(
                            Metrics.shape.strokeBorder(
                                isSelected ? Color.accent : .macLine,
                                lineWidth: isSelected ? Metrics.selectedBorder : .borderWidthHairline
                            )
                        )
                    Text(mode.title)
                        .type(.body2(isSelected ? .semibold : .regular))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        @ViewBuilder
        private func swatch(_ mode: AppearanceMode) -> some View {
            switch mode {
            case .system:
                HStack(spacing: .zero) {
                    Color.macChrome.environment(\.colorScheme, .light)
                    Color.macChrome.environment(\.colorScheme, .dark)
                }
            case .light, .dark:
                GeometryReader { proxy in
                    HStack(spacing: .zero) {
                        Color.macChrome
                            .frame(width: proxy.size.width * Metrics.sidebarFraction)
                        Color.macCard
                    }
                }
                .environment(\.colorScheme, mode == .dark ? .dark : .light)
            }
        }
    }

    #Preview("Appearance tiles") {
        @Previewable @State var mode = AppearanceMode.system
        MacAppearanceTiles(selection: $mode)
            .padding()
            .background(Color.macCard)
            .previewCanvas(.settingsPane)
    }
#endif
