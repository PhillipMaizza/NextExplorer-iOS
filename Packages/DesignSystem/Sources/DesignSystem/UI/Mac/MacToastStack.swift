#if os(macOS)
    import SwiftUI

    private enum Metrics {
        static let edgeInset: CGFloat = .space32
        static let maxVisible = 3
        static let peek: CGFloat = 14
        static let shrink: CGFloat = 0.05
        static let spreadGap: CGFloat = .space8
    }

    public extension View {
        func macToastPane() -> some View {
            overlay(alignment: .bottomTrailing) {
                MacToastPane()
            }
        }
    }

    private struct MacToastPane: View {
        private let center = MacToastCenter.shared

        var body: some View {
            if center.renderer == .pane {
                MacToastStack(center: center)
                    .padding(Metrics.edgeInset)
            }
        }
    }

    struct MacToastHost: View {
        @Binding var message: DSToastMessage?
        let extraBottomInset: CGFloat

        @State private var owner = UUID()
        @Environment(\.routesToastsToPane) private var routesToPane
        private let center = MacToastCenter.shared

        private var surface: MacToastCenter.Surface {
            routesToPane ? .pane : .host(owner)
        }

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .allowsHitTesting(false)
                if center.renderer == .host(owner) {
                    MacToastStack(center: center)
                        .padding(.trailing, Metrics.edgeInset)
                        .padding(.bottom, Metrics.edgeInset + extraBottomInset)
                }
            }
            .onAppear { center.update(from: nil, to: message, owner: owner, surface: surface, clear: clear) }
            .onChange(of: message) { old, new in
                center.update(from: old, to: new, owner: owner, surface: surface, clear: clear)
            }
            .onDisappear { center.hostGone(owner) }
        }

        private func clear(_ id: String) {
            if message?.id == id {
                message = nil
            }
        }
    }

    struct MacToastStack: View {
        let center: MacToastCenter

        @State private var isExpanded = false
        @State private var heights: [String: CGFloat] = [:]

        private var shown: [MacToastCenter.Entry] {
            Array(center.entries.suffix(Metrics.maxVisible))
        }

        private func height(_ entry: MacToastCenter.Entry) -> CGFloat {
            heights[entry.id] ?? .zero
        }

        private var frontHeight: CGFloat {
            shown.reversed().lazy.compactMap { heights[$0.id] }.first ?? .zero
        }

        private func lift(rank: Int) -> CGFloat {
            guard isExpanded else { return Metrics.peek * CGFloat(rank) }
            return shown.suffix(rank).reduce(.zero) { $0 + height($1) + Metrics.spreadGap }
        }

        private var stackHeight: CGFloat {
            frontHeight + lift(rank: max(shown.count - 1, 0))
        }

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    let rank = shown.count - 1 - index
                    let isCollapsedBehind = rank > 0 && !isExpanded
                    MacToastCard(
                        message: entry.message,
                        collapsedHeight: isCollapsedBehind ? frontHeight : nil,
                        onAction: { center.run(entry.id) },
                        onClose: { center.dismiss(entry.id) },
                        onHeight: { heights[entry.id] = $0 }
                    )
                    .scaleEffect(isExpanded ? 1 : 1 - Metrics.shrink * CGFloat(rank), anchor: .top)
                    .offset(y: -lift(rank: rank))
                    .allowsHitTesting(!isCollapsedBehind)
                    .zIndex(Double(index))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: stackHeight, alignment: .bottom)
            .contentShape(Rectangle())
            .onHover { isHovering in
                withAnimation(DSMotion.toast) { isExpanded = isHovering }
                center.setPaused(isHovering)
            }
            .animation(DSMotion.toast, value: shown.map(\.id))
            .onChange(of: center.entries.map(\.id)) { _, ids in
                heights = heights.filter { ids.contains($0.key) }
            }
        }
    }

    #Preview("Three stacked") {
        let center = MacToastCenter()
        let owner = UUID()
        center.update(from: nil, to: .progress("Compressing…"), owner: owner, surface: .pane) { _ in }
        center
            .update(
                from: nil,
                to: .success("6 files uploaded", detail: "Clients"),
                owner: UUID(),
                surface: .pane
            ) { _ in
            }
        center.update(
            from: nil,
            to: .success("1 item moved to the trash", actionTitle: "Open Trash") {},
            owner: UUID(),
            surface: .pane
        ) { _ in }
        return MacToastStack(center: center)
            .padding(.space40)
            .frame(width: 480, height: 320, alignment: .bottomTrailing)
            .background(Color.macChrome)
    }
#endif
