#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import SwiftUI

    private enum Metrics {
        static let notificationWidth: CGFloat = 360
        static let notificationHeight: CGFloat = 150
        static let notificationInset: CGFloat = .space48
    }

    enum TransferQueue: String {
        case uploads
        case downloads
    }

    struct MacTransferButtonAnchorKey: PreferenceKey {
        static var defaultValue: [TransferQueue: Anchor<CGRect>] {
            [:]
        }

        static func reduce(
            value: inout [TransferQueue: Anchor<CGRect>],
            nextValue: () -> [TransferQueue: Anchor<CGRect>]
        ) {
            value.merge(nextValue()) { $1 }
        }
    }

    extension View {
        func macTransferButtonAnchor(_ queue: TransferQueue) -> some View {
            anchorPreference(key: MacTransferButtonAnchorKey.self, value: .bounds) { [queue: $0] }
        }
    }

    struct MacTransferPanelLayer: View {
        let store: StoreOf<MainTabFeature>
        let onUploadMore: (() -> Void)?
        let closedNotifications: Set<TransferQueue>
        let buttonAnchors: [TransferQueue: Anchor<CGRect>]

        @Environment(\.colorScheme) private var colorScheme

        private var isShown: Bool {
            store.uploads.isSheetPresented || store.downloadQueue.isSheetPresented
        }

        private var scrimOpacity: Double {
            colorScheme == .dark ? MacPeekMetrics.scrimDarkOpacity : MacPeekMetrics.scrimLightOpacity
        }

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    if isShown {
                        Color.black.opacity(scrimOpacity)
                            .ignoresSafeArea()
                            .onTapGesture(perform: dismiss)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                    if store.uploads.isSheetPresented {
                        UploadsView(
                            store: store.scope(state: \.uploads, action: \.uploads),
                            onUploadMore: onUploadMore
                        )
                        .transition(transition(.uploads, isActive: store.uploads.isActive, in: proxy))
                    } else if store.downloadQueue.isSheetPresented {
                        DownloadQueueView(store: store.scope(state: \.downloadQueue, action: \.downloadQueue))
                            .transition(transition(.downloads, isActive: store.downloadQueue.isActive, in: proxy))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .allowsHitTesting(isShown)
            .animation(isShown ? DSMotion.sheetPresent : DSMotion.sheetDismiss, value: isShown)
        }

        private func dismiss() {
            if store.uploads.isSheetPresented {
                store.send(.uploads(.sheetPresented(false)))
            } else {
                store.send(.downloadQueue(.sheetPresented(false)))
            }
        }

        private func transition(_ queue: TransferQueue, isActive: Bool, in proxy: GeometryProxy) -> AnyTransition {
            guard let target = target(queue, isActive: isActive, in: proxy) else {
                return .scale(scale: MacPeekMetrics.zoomScale).combined(with: .opacity)
            }
            return AnyTransition(PanelMorph(
                offset: CGSize(width: target.midX - proxy.size.width / 2, height: target.midY - proxy.size.height / 2),
                scale: target.width / MacTransferQueueMetrics.width
            ))
        }

        private func target(_ queue: TransferQueue, isActive: Bool, in proxy: GeometryProxy) -> CGRect? {
            if isActive, !closedNotifications.contains(queue) {
                return CGRect(
                    x: proxy.size.width - Metrics.notificationInset - Metrics.notificationWidth,
                    y: proxy.size.height - Metrics.notificationInset - Metrics.notificationHeight,
                    width: Metrics.notificationWidth,
                    height: Metrics.notificationHeight
                )
            }
            return buttonAnchors[queue].map { proxy[$0] }
        }
    }

    private struct PanelMorph: Transition {
        let offset: CGSize
        let scale: CGFloat

        func body(content: Content, phase: TransitionPhase) -> some View {
            content
                .scaleEffect(phase.isIdentity ? 1 : scale)
                .offset(phase.isIdentity ? .zero : offset)
                .opacity(phase.isIdentity ? 1 : 0)
        }
    }

    #Preview("Uploads panel") {
        var state = MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User.preview
        )
        state.uploads.isSheetPresented = true
        return Color.macChrome
            .overlay {
                MacTransferPanelLayer(
                    store: Store(initialState: state) { MainTabFeature() },
                    onUploadMore: {},
                    closedNotifications: [],
                    buttonAnchors: [:]
                )
            }
            .frame(width: 1000, height: 700)
    }
#endif
