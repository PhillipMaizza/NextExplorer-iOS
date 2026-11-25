#if os(macOS)
    import DesignSystem
    import SwiftUI

    struct MacInspectorPane<Inspector: View>: ViewModifier {
        let isOpen: Bool
        var onOpen: (() -> Void)?
        let onClose: () -> Void
        @ViewBuilder let inspector: () -> Inspector

        func body(content: Content) -> some View {
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity)
                    .clipped()
                if isOpen {
                    inspector()
                        .macInspectorColumn()
                }
            }
            .animation(DSMotion.stateFade, value: isOpen)
            .onExitCommand(perform: isOpen ? onClose : nil)
            .focusedSceneValue(\.closeMacInspector, isOpen ? MacInspectorAction(perform: onClose) : nil)
            .focusedSceneValue(\.openMacInspector, isOpen ? nil : onOpen.map { MacInspectorAction(perform: $0) })
        }
    }

    extension View {
        func macInspectorPane(
            isOpen: Bool,
            onOpen: (() -> Void)? = nil,
            onClose: @escaping () -> Void,
            @ViewBuilder inspector: @escaping () -> some View
        ) -> some View {
            modifier(MacInspectorPane(isOpen: isOpen, onOpen: onOpen, onClose: onClose, inspector: inspector))
        }
    }

    private struct MacInspectorPanePreview: View {
        @State var isOpen: Bool

        var body: some View {
            Color.macChrome
                .macInspectorPane(isOpen: isOpen, onOpen: { isOpen = true }, onClose: { isOpen = false }) {
                    Color.macCard
                }
                .padding(.space24)
                .frame(width: MacPeekMetrics.previewWidth, height: MacPeekMetrics.previewHeight)
        }
    }

    #Preview("Open") {
        MacInspectorPanePreview(isOpen: true)
    }

    #Preview("Closed") {
        MacInspectorPanePreview(isOpen: false)
    }
#endif
