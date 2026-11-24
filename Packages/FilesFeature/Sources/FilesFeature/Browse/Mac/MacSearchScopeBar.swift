#if os(macOS)
    import AppKit
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let chipHeight: CGFloat = 26
        static let glyphSize: CGFloat = .size12
    }

    struct MacSearchScopeBar: View {
        let availableCategories: [FileCategory]
        let counts: [FileCategory: Int]
        let selectedCategories: Set<FileCategory>
        let onToggle: (FileCategory) -> Void
        let onShowAll: () -> Void

        var body: some View {
            if !availableCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .size6) {
                        Button(action: onShowAll) {
                            chipLabel(L10n.Filter.all, count: counts.values.reduce(0, +))
                        }
                        .buttonStyle(MacScopeChipStyle(isSelected: selectedCategories.isEmpty))
                        ForEach(availableCategories) { category in
                            Button { pick(category) } label: {
                                chipLabel(category.title, count: counts[category] ?? 0, icon: category.icon)
                            }
                            .buttonStyle(MacScopeChipStyle(isSelected: selectedCategories.contains(category)))
                        }
                    }
                    .padding(.horizontal, MacPaneInset.sectionHeader)
                }
                .scrollClipDisabled()
                .padding(.bottom, .space12)
            }
        }

        private func chipLabel(_ title: String, count: Int, icon: Image? = nil) -> some View {
            HStack(spacing: .size6) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.glyphSize, height: Metrics.glyphSize)
                        .accessibilityHidden(true)
                }
                Text(title)
                Text(count, format: .number)
                    .monospacedDigit()
                    .opacity(MacScopeChipStyle.countOpacity)
            }
        }

        private func pick(_ category: FileCategory) {
            if NSEvent.modifierFlags.contains(.command) {
                onToggle(category)
            } else if selectedCategories == [category] {
                onShowAll()
            } else {
                onShowAll()
                onToggle(category)
            }
        }
    }

    private struct MacScopeChipStyle: ButtonStyle {
        static let countOpacity = 0.6
        static let pressedOpacity = 0.75

        let isSelected: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .type(.label4)
                .foregroundStyle(isSelected ? Color.onAccent : Color.macChromeText)
                .padding(.horizontal, .space12)
                .frame(height: Metrics.chipHeight)
                .background(Capsule().fill(isSelected ? Color.accent : Color.macCard))
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.macLine))
                .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
                .contentShape(Capsule())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    #Preview("Kinds") {
        MacSearchScopeBar(
            availableCategories: [.folder, .image, .document],
            counts: [.folder: 1, .image: 2, .document: 3],
            selectedCategories: [.image],
            onToggle: { _ in },
            onShowAll: {}
        )
        .previewCanvasWidth(.sheet)
    }

    #Preview("All") {
        MacSearchScopeBar(
            availableCategories: [.folder, .image, .document, .archive],
            counts: [.folder: 1, .image: 2, .document: 2, .archive: 1],
            selectedCategories: [],
            onToggle: { _ in },
            onShowAll: {}
        )
        .previewCanvasWidth(.sheet)
        .preferredColorScheme(.dark)
    }
#endif
