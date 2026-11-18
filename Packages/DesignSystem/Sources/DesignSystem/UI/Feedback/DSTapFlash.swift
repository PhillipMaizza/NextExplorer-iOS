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
            try? await DSMotion.waitForStep(Constants.holdDuration)
            if reduceMotion {
                isFlashing = false
            } else {
                withAnimation(DSMotion.fadeOut) { isFlashing = false }
            }
        }
    }
}

/// Hands the flash of `dsTapFlashSource` down to the content, which draws it with
/// `dsTapFlashHighlight` on only the part that should light up.
private struct TapFlashSource: ViewModifier {
    let isEnabled: Bool
    @State private var isFlashing = false

    func body(content: Content) -> some View {
        content
            .environment(\.isTapFlashing, isEnabled && isFlashing)
            .modifier(TapFlash(isFlashing: $isFlashing))
    }
}

private struct TapFlashHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.isTapFlashing) private var isFlashing

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.accent.opacity(Constants.flashOpacity))
                .opacity(isFlashing ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

public extension EnvironmentValues {
    @Entry var isTapFlashing = false
}

public extension View {
    /// Catches the tap for a flash but leaves drawing it to the content (iOS). Apply to the button,
    /// not inside its label: a tap gesture inside a label takes the tap from the button. Off while
    /// `isEnabled` is false, such as in select mode, where the selection itself answers the tap.
    func dsTapFlashSource(isEnabled: Bool = true) -> some View {
        #if os(iOS)
            modifier(TapFlashSource(isEnabled: isEnabled))
        #else
            self
        #endif
    }

    /// Draws the flash of the nearest `dsTapFlashSource` over this view only, such as a tile's picture.
    func dsTapFlashHighlight(cornerRadius: CGFloat = .radiusCard) -> some View {
        modifier(TapFlashHighlight(cornerRadius: cornerRadius))
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
                .background(
                    Color.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
                )
                .dsTapFlashHighlight()
                .dsTapFlashSource()
            List {
                DSFlashingListRow { Text("Documents") }
                DSFlashingListRow { Text("Photos") }
            }
        }
        .padding(.space16)
    }
#endif
