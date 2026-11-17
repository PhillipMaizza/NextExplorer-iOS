import SwiftUI

private enum Constants {
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space8
    static let bottomPadding: CGFloat = .space24
}

/// The pinned action strip every presented card sheet shares: whatever buttons a sheet puts
/// in `DSDynamicHeightSheet`'s `footer:` closure, wrapped with the one standard padding.
///
/// On iOS the strip sits straight on the sheet's frosted surface (a second surface would read as a
/// darker band), and the system's scroll edge effect keeps it legible over scrolling content. On a
/// Mac an opaque `backgroundPrimary` fill does that; either way there is deliberately no `Divider()`.
public struct DSSheetFooter<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.top, Constants.topPadding)
            .padding(.bottom, Constants.bottomPadding)
            .frame(maxWidth: .infinity)
        #if os(macOS)
            .background(Color.backgroundPrimary)
        #endif
    }
}

#Preview("Single button") {
    DSSheetFooter {
        DSButton("Save", style: .primary) {}
    }
    .background(Color.backgroundSecondary)
}

#Preview("Cancel / Save") {
    DSSheetFooter {
        HStack(spacing: .space12) {
            DSButton("Cancel", style: .ghost) {}
            DSButton("Save", style: .primary) {}
        }
    }
    .background(Color.backgroundSecondary)
}
