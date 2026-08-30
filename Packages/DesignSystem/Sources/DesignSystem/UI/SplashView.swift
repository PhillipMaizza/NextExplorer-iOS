import SwiftUI

private enum Constants {
    static let logoSize: CGFloat = 160

    static let hold: Double = 0.12
    static let spinDuration: Double = 0.68

    static let shineBandWidth: CGFloat = 80
    static let shineDuration: Double = 1.25
    static let shineOpacity: Double = 0.85

    static let flapStep: Double = 0.15
    static let partDuration: Double = 0.5

    /// Hard cap: however slow (or stuck) the app's readiness check is, the splash never holds
    /// the screen longer than this before clearing itself.
    static let maxOnScreen: Double = 10
}

/// The launch splash. Picks up where `LaunchScreen.storyboard` leaves off — the app mark
/// still on the launch gradient — twirls it once in 3D, sweeps a shine across it, then (once
/// `isReady`) gives it two quick butterfly flaps and opens the wings apart, sliding them off
/// while the gradient fades to reveal whatever is behind. `onFinished` fires when it clears.
///
/// Minimum on-screen time is the flourish length (~2s) even when `isReady` is already true;
/// maximum is `Constants.maxOnScreen`, after which it clears regardless.
public struct SplashView: View {
    private let isReady: Bool
    private let onExitStarted: () -> Void
    private let onFinished: () -> Void

    /// `onExitStarted` fires the instant the splash commits to leaving, while it still fully
    /// covers the screen — the moment for the caller to mount whatever is behind it, so the
    /// wing-opening reveal uncovers real content rather than a blank frame. `onFinished`
    /// fires once it has cleared.
    public init(
        isReady: Bool,
        onExitStarted: @escaping () -> Void = {},
        onFinished: @escaping () -> Void
    ) {
        self.isReady = isReady
        self.onExitStarted = onExitStarted
        self.onFinished = onFinished
    }

    @State private var spin: Double = 0
    @State private var flap: Double = 0
    @State private var part: Double = 0
    @State private var shine: CGFloat = -1
    @State private var fade: Double = 1

    /// `@State` mirrors so the exit trigger only ever reads live values — a captured `isReady`
    /// inside `.task` goes stale and would strand the splash on screen.
    @State private var readyLatch = false
    @State private var didSettle = false
    @State private var isExiting = false

    public var body: some View {
        ZStack {
            Color.clear
            mark
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .backgroundGradient()
        .opacity(fade)
        .task { await run() }
        .onAppear { if isReady { readyLatch = true } }
        .onChange(of: isReady) { _, new in if new { readyLatch = true } }
        .onChange(of: readyLatch) { _, _ in maybeExit() }
        .onChange(of: didSettle) { _, _ in maybeExit() }
    }

    private var mark: some View {
        DSLogoMark(spin: spin, flap: flap, part: part, size: Constants.logoSize)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(Constants.shineOpacity), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Constants.shineBandWidth)
                .offset(x: shine * (Constants.logoSize + Constants.shineBandWidth))
                .frame(width: Constants.logoSize, height: Constants.logoSize)
                .mask { DSLogoMark(spin: spin, size: Constants.logoSize) }
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
    }

    private func run() async {
        try? await Task.sleep(for: .seconds(Constants.hold))

        withAnimation(.easeInOut(duration: Constants.spinDuration)) { spin = 1 }
        try? await Task.sleep(for: .seconds(Constants.spinDuration))

        withAnimation(.easeInOut(duration: Constants.shineDuration)) { shine = 1 }
        try? await Task.sleep(for: .seconds(Constants.shineDuration))

        didSettle = true
        maybeExit()

        // Safety net: clear no matter what.
        try? await Task.sleep(for: .seconds(Constants.maxOnScreen))
        if !isExiting { onFinished() }
    }

    private func maybeExit() {
        guard didSettle, readyLatch, !isExiting else { return }
        isExiting = true
        onExitStarted()

        Task { @MainActor in
            withAnimation(.easeInOut(duration: Constants.flapStep)) { flap = 0.8 }
            try? await Task.sleep(for: .seconds(Constants.flapStep))
            withAnimation(.easeInOut(duration: Constants.flapStep)) { flap = -0.45 }
            try? await Task.sleep(for: .seconds(Constants.flapStep))
            withAnimation(.easeInOut(duration: Constants.flapStep)) { flap = 0 }

            withAnimation(.easeIn(duration: Constants.partDuration)) {
                part = 1
                fade = 0
            }
            try? await Task.sleep(for: .seconds(Constants.partDuration))
            onFinished()
        }
    }
}

#Preview("Flourishing") {
    SplashView(isReady: false, onFinished: {})
}

#Preview("Ready — butterfly opens") {
    ZStack {
        Color.clear.backgroundGradient().ignoresSafeArea()
        SplashView(isReady: true, onFinished: {})
    }
}
