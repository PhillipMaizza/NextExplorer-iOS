#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let height: CGFloat = .size40
        static let clearSize: CGFloat = .size24
        static let focusWidth: CGFloat = 3
        static let focusOpacity: Double = 0.4
    }

    struct MacTopBarSearch: View {
        let text: Binding<String>?
        var prompt = L10n.Spotlight.placeholder
        let openSpotlight: () -> Void

        @FocusState private var isFocused: Bool
        @State private var typedText = ""

        var body: some View {
            Group {
                if let text {
                    field(text)
                } else {
                    Button(action: openSpotlight) { pill(trailing: MacKeyHint(MacShortcutHint.search)) {
                        Text(L10n.Spotlight.placeholder)
                            .type(.body1(.regular))
                            .lineLimit(1)
                        Spacer(minLength: .zero)
                    } }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Common.search)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Search.field)
                }
            }
            .focusedSceneValue(\.focusSearchField, text == nil ? nil : FocusSearchAction { isFocused = true })
        }

        private func field(_ text: Binding<String>) -> some View {
            pill(trailing: trailing(text)) {
                TextField(
                    L10n.Common.search,
                    text: Binding(
                        get: { text.wrappedValue },
                        set: {
                            typedText = $0
                            text.wrappedValue = $0
                        }
                    ),
                    prompt: Text(prompt)
                        .foregroundStyle(Color.macChromeSecondary)
                )
                .textFieldStyle(.plain)
                .type(.body1(.regular))
                .foregroundStyle(Color.macChromeText)
                .tint(Color.accent)
                .autocorrectionDisabled()
                .focused($isFocused)
                .onExitCommand {
                    text.wrappedValue = ""
                    isFocused = false
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Search.field)
            }
            .contentShape(Capsule())
            .onTapGesture { isFocused = true }
            .onChange(of: text.wrappedValue) { _, newText in
                guard newText != typedText else { return }
                typedText = newText
                isFocused = false
            }
            .focusEffectDisabled()
            .overlay {
                Capsule()
                    .strokeBorder(Color.accent.opacity(Metrics.focusOpacity), lineWidth: Metrics.focusWidth)
                    .padding(-Metrics.focusWidth)
                    .opacity(isFocused ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(DSMotion.quickFade, value: text.wrappedValue.isEmpty)
            .animation(DSMotion.quickFade, value: isFocused)
        }

        @ViewBuilder
        private func trailing(_ text: Binding<String>) -> some View {
            if !text.wrappedValue.isEmpty {
                Button {
                    typedText = ""
                    text.wrappedValue = ""
                } label: {
                    IconKit.closeCircle
                        .foregroundStyle(Color.macChromeSecondary)
                        .frame(width: Metrics.clearSize, height: Metrics.clearSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabelWithTooltip(L10n.Common.clear)
                .transition(.opacity)
            } else {
                MacKeyHint(isFocused ? MacShortcutHint.escape : MacShortcutHint.find)
                    .accessibilityHidden(true)
            }
        }

        private func pill(
            trailing: some View,
            @ViewBuilder content: () -> some View
        ) -> some View {
            HStack(spacing: .space8) {
                IconKit.macToolbarSearch.macToolbarGlyph()
                content()
                trailing
            }
            .foregroundStyle(Color.macChromeSecondary)
            .padding(.leading, .space16)
            .padding(.trailing, .space8)
            .frame(maxWidth: .infinity, minHeight: Metrics.height)
            .background(Capsule().fill(Color.macChromeButton))
            .contentShape(Capsule())
        }
    }

    public extension FocusedValues {
        @Entry var macSearchText: Binding<String>?
    }

    #Preview("Search, idle") {
        MacTopBarSearch(text: .constant("")) {}
            .padding()
            .previewCanvasWidth(.dialog)
            .background(Color.macChrome)
    }

    #Preview("Search, typed") {
        MacTopBarSearch(text: .constant("notes")) {}
            .padding()
            .previewCanvasWidth(.dialog)
            .background(Color.macChrome)
    }

    #Preview("Search, shares") {
        MacTopBarSearch(text: .constant(""), prompt: L10n.Shared.searchPrompt) {}
            .padding()
            .previewCanvasWidth(.dialog)
            .background(Color.macChrome)
    }

    #Preview("Search, no field") {
        MacTopBarSearch(text: nil) {}
            .padding()
            .previewCanvasWidth(.dialog)
            .background(Color.macChrome)
    }
#endif
