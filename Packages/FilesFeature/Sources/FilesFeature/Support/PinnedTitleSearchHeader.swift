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
        .roundedFieldStyle(isFocused: isFocused)
        .runningDashBorder(
                isFocused: isFocused,
                color: .accent,
                cornerRadius: .radiusLarge,
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
struct RunningDashBorderModifier: ViewModifier {
    let isFocused: Bool
    let color: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: color, location: 0.0),
                        .init(color: .clear, location: 0.5),
                        .init(color: color, location: 1.0)
                    ]),
                    center: .center
                )
                .rotationEffect(.degrees(angle))
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(lineWidth: lineWidth)
                )
                .opacity(isFocused ? 1 : 0)
            )
            .onChange(of: isFocused) { _, focused in
                if focused {
                    angle = 0
                    withAnimation(
                        .linear(duration: 2.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        angle = 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        angle = 0
                    }
                }
            }
    }
}

extension View {
    func runningDashBorder(
        isFocused: Bool,
        color: Color = .accent,
        cornerRadius: CGFloat = .radiusLarge,
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
