import SwiftUI

/// A file or folder that lights up the moment it is tapped, like CSS's `:active`, so the tap is
/// acknowledged before the next screen arrives. It flashes from the tap itself rather than from
/// the button's pressed state: inside a list or scroll view iOS only reports "pressed" once it is
/// sure the touch is not a scroll, and a quick tap is over by then. The flash holds for a moment
/// and fades out, so it is visible while the folder loads.
///
/// iOS only. The Mac acknowledges a click natively (table selection, hover), so there these do
/// nothing beyond what the content already does.
private enum Constants {
    static let flashOpacity: Double = 0.16
    static let holdDuration: Duration = .milliseconds(90)
    static let fadeDuration: Double = 0.4
}

/// The flash as state, shared by the card and list row variants.
@MainActor
private struct TapFlash: ViewModifier {
    @Binding var isFlashing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded { flash() })
    }

    private func flash() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { isFlashing = true }
        Task { @MainActor in
            try? await Task.sleep(for: Constants.holdDuration)
            if reduceMotion {
                isFlashing = false
            } else {
                withAnimation(.easeOut(duration: Constants.fadeDuration)) { isFlashing = false }
            }
        }
    }
}

private struct TapFlashOverlay: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isFlashing = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accent.opacity(Constants.flashOpacity))
                    .opacity(isFlashing ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .modifier(TapFlash(isFlashing: $isFlashing))
    }
}

public extension View {
    /// Flashes over the whole view when it is tapped (iOS). Apply to the view that is the cell,
    /// such as a card, so the flash is as wide and tall as the cell.
    func dsTapFlash(cornerRadius: CGFloat = .radiusCard) -> some View {
        #if os(iOS)
            modifier(TapFlashOverlay(cornerRadius: cornerRadius))
        #else
            self
        #endif
    }
}

/// A list row that flashes across the whole row, edge to edge, when it is tapped (iOS). The flash is
/// the row's background rather than an overlay on its content, because a list gives the content
/// an inset and the flash should fill the cell. Takes the place of `.listRowBackground`.
public struct DSFlashingListRow<Content: View>: View {
    private let content: Content
    @State private var isFlashing = false

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        #if os(iOS)
            content
                .modifier(TapFlash(isFlashing: $isFlashing))
                .listRowBackground(
                    ZStack {
                        Color.backgroundSecondary
                        Color.accent.opacity(Constants.flashOpacity).opacity(isFlashing ? 1 : 0)
                    }
                )
        #else
            content.listRowBackground(Color.backgroundSecondary)
        #endif
    }
}

#if DEBUG
    #Preview("Flash states") {
        VStack(spacing: .space16) {
            Text("Tap me").padding(.space16).frame(maxWidth: .infinity)
                .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
                .dsTapFlash()
            List {
                DSFlashingListRow { Text("Documents") }
                DSFlashingListRow { Text("Photos") }
            }
        }
        .padding(.space16)
    }
#endif
