#if os(macOS)
    import CoreModels
    import DesignSystem
    import SwiftUI

    @MainActor
    @Observable
    final class MacPeekHost {
        private(set) var card: AnyView?
        private var owner: ObjectIdentifier?
        private var onClose: () -> Void = {}

        func show(_ card: some View, owner: ObjectIdentifier, onClose: @escaping () -> Void) {
            self.card = AnyView(card)
            self.owner = owner
            self.onClose = onClose
        }

        func hide(owner: ObjectIdentifier) {
            guard self.owner == owner else { return }
            card = nil
            self.owner = nil
            onClose = {}
        }

        func close() {
            onClose()
        }
    }

    struct MacPeekLayer: View {
        let host: MacPeekHost
        @Environment(\.colorScheme) private var colorScheme

        private var scrimOpacity: Double {
            colorScheme == .dark ? MacPeekMetrics.scrimDarkOpacity : MacPeekMetrics.scrimLightOpacity
        }

        var body: some View {
            ZStack {
                if let card = host.card {
                    Color.black.opacity(scrimOpacity)
                        .ignoresSafeArea()
                        .onTapGesture { host.close() }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    card
                        .padding(MacPeekMetrics.margin)
                        .transition(.scale(scale: MacPeekMetrics.zoomScale).combined(with: .opacity))
                }
            }
            .animation(DSMotion.stateFade, value: host.card != nil)
        }
    }

    private struct MacPeekHosting: ViewModifier {
        @State private var host = MacPeekHost()

        func body(content: Content) -> some View {
            content
                .overlay { MacPeekLayer(host: host) }
                .environment(host)
        }
    }

    extension View {
        func macPeekHosting() -> some View {
            modifier(MacPeekHosting())
        }
    }

    #Preview("Peek over a window") {
        let host = MacPeekHost()
        host.show(
            FileSummaryView(
                item: FileItem(name: "installer.dmg", path: "", dateModified: .distantPast, size: 16_384, kind: "dmg"),
                message: nil
            )
            .frame(maxWidth: MacPeekMetrics.maxWidth, maxHeight: MacPeekMetrics.previewHeight)
            .background(Color.macCard),
            owner: ObjectIdentifier(host)
        ) {}
        return Color.macChrome
            .overlay { MacPeekLayer(host: host) }
            .frame(width: MacPeekMetrics.maxWidth, height: MacPeekMetrics.maxHeight)
    }
#endif
