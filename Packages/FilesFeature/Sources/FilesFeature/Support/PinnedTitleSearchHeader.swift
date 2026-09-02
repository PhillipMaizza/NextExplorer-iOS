import DesignSystem
import Localization
import SwiftUI

/// A large title and an always-visible search field pinned ABOVE the scrolling list, instead of
/// in the navigation bar. A system large title only stays large while the scroll offset is 0 and
/// collapses to inline the instant the content settles below an always-on `.searchable` drawer
/// (or a fresh scroll container lands its offset there on load). Rendering the title and search
/// as ordinary pinned content sidesteps that entirely: the title never collapses and the search
/// field never scrolls away.
///
/// The host keeps its navigation bar for the back button and toolbar actions, but with the
/// system title hidden (`.navigationBarTitleDisplayMode(.inline)` + no title text).
struct PinnedTitleSearchHeader<Accessory: View>: View {
    let title: String
    @Binding var searchText: String
    var prompt: String = L10n.Common.search
    /// Extra padding above the title. A screen whose nav bar carries no toolbar actions (e.g.
    /// Settings) sits higher than one that does; pass the actions' height here so every tab's
    /// title lines up.
    var extraTopPadding: CGFloat = 0
    /// Rendered below the search field, e.g. a search-scope segmented control while searching.
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .space12) {
            Text(title)
                .type(.headline2, style: .primary(for: .label))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            searchField
            accessory()
        }
        .padding(.horizontal, .space16)
        .padding(.top, .space8 + extraTopPadding)
        .padding(.bottom, .space12)
        // Solid top color behind the title/search (matches the `backgroundGradient()` top stop,
        // so it reads seamless) so scrolled rows never bleed through the header. A short fade
        // tail sits just below the header edge to melt into the list gradient instead of ending
        // on a hard band.
        .background(Color.backgroundGradientTop.ignoresSafeArea(edges: .top))
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [Color.backgroundGradientTop, Color.backgroundGradientTop.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: .space16)
            .offset(y: .space16)
        }
    }

    private var searchField: some View {
        HStack(spacing: .space8) {
            IconKit.search
                .foregroundStyle(Color.secondaryDS)
            TextField(
                text: $searchText,
                prompt: Text(prompt).foregroundColor(Color.secondaryDS)
            ) { EmptyView() }
                .focused($isFocused)
                .type(.body1(.regular))
                .tint(Color.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    IconKit.closeCircle.foregroundStyle(Color.secondaryDS)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)
        .roundedFieldStyle()
        .runningDashBorder(
                isFocused: isFocused,
                color: .accent,
                cornerRadius: .radiusControl,
                lineWidth: 2
            )
    }
}

extension PinnedTitleSearchHeader where Accessory == EmptyView {
    init(
        title: String,
        searchText: Binding<String>,
        prompt: String = L10n.Common.search,
        extraTopPadding: CGFloat = 0
    ) {
        self.init(title: title, searchText: searchText, prompt: prompt, extraTopPadding: extraTopPadding) { EmptyView() }
    }
}
/// A comet of light that laps the field's border while it's focused: a bright head with a tail
/// that fades to nothing, gliding around a `trim`med rounded rect perimeter (aspect independent,
/// unlike an `AngularGradient` mask, which pools into two marks on a wide short field). Each lap
/// eases in and out — accelerating away from the seam, decelerating back into it — and the whole
/// comet fades up at the start of a lap and fades away as it finishes, so the loop restarts on a
/// soft pulse rather than a hard jump. Driven by a `TimelineView` clock so position, tail fade
/// and the per lap envelope are all derived from one time value.
struct RunningDashBorderModifier: ViewModifier {
    let isFocused: Bool
    let color: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    /// Length of the comet (head to tail) as a fraction of the total perimeter. Well under 1 so a
    /// gap always remains and it reads as a moving segment, not a closed border.
    private let cometLength: CGFloat = 0.35
    /// The tail is built from this many arcs, all ending at the head and each a little longer, so
    /// their translucent overlap accumulates into a smooth head→tail fade.
    private let tailSteps = 16
    /// Per arc opacity. Low, so `tailSteps` of overlap reach near opaque at the head while a lone
    /// arc at the tail is nearly clear.
    private let layerOpacity: Double = 0.16
    private let lapDuration: Double = 4.0

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFocused {
                    cometOverlay.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isFocused)
    }

    private var cometOverlay: some View {
        TimelineView(.animation) { timeline in
            let cycle = (timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: lapDuration)) / lapDuration
            // Smoothstep the lap position so it accelerates out of the seam and decelerates back
            // into it (the spring-like ease), and a sine envelope so the comet fades up at the
            // lap start and away as it finishes.
            let head = CGFloat(smoothstep(cycle))
            let envelope = sin(.pi * cycle)

            cometTrail(head: head)
                .opacity(envelope)
        }
    }

    /// The comet as `tailSteps` arcs that all end at the head and grow toward the tail, each at a
    /// low opacity. Where many overlap (the head) the color builds to near opaque; toward the tail,
    /// where only the longest arcs reach, it thins to nothing — a smooth fade with no beading.
    private func cometTrail(head: CGFloat) -> some View {
        let inset = lineWidth / 2
        return ZStack {
            ForEach(0..<tailSteps, id: \.self) { index in
                let length = cometLength * CGFloat(index + 1) / CGFloat(tailSteps)
                BorderArcShape(
                    from: head - length,
                    length: length,
                    cornerRadius: cornerRadius,
                    inset: inset
                )
                .stroke(
                    color.opacity(layerOpacity),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                )
            }
        }
    }

    /// Cubic smoothstep: 0→1 with zero velocity at both ends.
    private func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// One arc of the rounded rect perimeter, `length` long starting at `from` (both in 0…1 of the
/// perimeter), wrapping across the 1→0 seam so a slice straddling a corner never breaks.
private struct BorderArcShape: Shape {
    var from: CGFloat
    var length: CGFloat
    var cornerRadius: CGFloat
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let base = Path(
            roundedRect: rect.insetBy(dx: inset, dy: inset),
            cornerRadius: cornerRadius
        )
        let start = ((from.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
        let end = start + length
        if end <= 1 {
            return base.trimmedPath(from: start, to: end)
        }
        var wrapped = base.trimmedPath(from: start, to: 1)
        wrapped.addPath(base.trimmedPath(from: 0, to: end - 1))
        return wrapped
    }
}

extension View {
    func runningDashBorder(
        isFocused: Bool,
        color: Color = .accent,
        cornerRadius: CGFloat = .radiusControl,
        lineWidth: CGFloat = 2
    ) -> some View {
        modifier(RunningDashBorderModifier(
            isFocused: isFocused,
            color: color,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth
        ))
    }
}
