import SwiftUI

private enum Constants {
    static let dimOpacity: Double = 0.3
    static let cardMargin: CGFloat = .space8
    static let presentAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.9)
    static let dismissAnimation: Animation = .easeIn(duration: 0.2)
}

public extension EnvironmentValues {
    /// True while a card sheet is hosted as a floating `dsSheet` card instead of a system sheet.
    @Entry var isDSCardSheet = false
}

public extension View {
    /// Presents a card sheet (`DSDynamicHeightSheet`, `DSAlertSheet`). A plain system sheet
    /// everywhere except iPhone Duo: an iPhone sheet always spans the whole window, there
    /// running under the vertical bar and stretching across the open or landscape panel, so it
    /// shows as a floating card inside the content area instead, at most `sheetCardMaxWidth`
    /// wide. Tapping outside sets the binding false, so a prompt with a no op setter stays modal.
    func dsSheet(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(DSSheetModifier(isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }

    func dsSheet<Item: Identifiable>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        modifier(DSItemSheetModifier(item: item, onDismiss: onDismiss, sheetContent: content))
    }
}

@MainActor
private var usesCardSheet: Bool {
    OrientationLock.shared.isFoldable
}

private struct DSSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent

    @State private var card = DSCardSheetState()

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(get: { isPresented && !usesCardSheet }, set: { isPresented = $0 }),
                onDismiss: onDismiss,
                content: sheetContent
            )
            .fullScreenCover(isPresented: $card.coverBinding { isPresented = false }, onDismiss: onDismiss) {
                DSCardSheetHost(isCardShown: $card.isCardShown, onBackgroundTap: { isPresented = false }) {
                    sheetContent()
                }
            }
            .onChange(of: isPresented, initial: true) { _, presented in
                guard usesCardSheet else { return }
                DSCardSheetState.update($card, presented: presented)
            }
    }
}

private struct DSItemSheetModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let sheetContent: (Item) -> SheetContent

    @State private var card = DSCardSheetState()
    /// Held past the binding going nil so the card keeps its content while it slides out.
    @State private var shownItem: Item?

    func body(content: Content) -> some View {
        content
            .sheet(
                item: Binding(get: { usesCardSheet ? nil : item }, set: { item = $0 }),
                onDismiss: onDismiss,
                content: sheetContent
            )
            .fullScreenCover(isPresented: $card.coverBinding { item = nil }, onDismiss: onDismiss) {
                DSCardSheetHost(isCardShown: $card.isCardShown, onBackgroundTap: { item = nil }) {
                    if let shownItem {
                        sheetContent(shownItem)
                    }
                }
            }
            .onChange(of: item?.id, initial: true) { _, _ in
                guard usesCardSheet else { return }
                if let item {
                    shownItem = item
                }
                DSCardSheetState.update($card, presented: item != nil)
            }
    }
}

/// The cover is presented and removed without the system slide (which would drag the dim along);
/// the card animates itself in on appear and out before the cover goes.
private struct DSCardSheetState {
    var isCoverPresented = false
    var isCardShown = false

    @MainActor
    static func update(_ state: Binding<DSCardSheetState>, presented: Bool) {
        if presented {
            if state.wrappedValue.isCoverPresented {
                withAnimation(Constants.presentAnimation) { state.wrappedValue.isCardShown = true }
            } else {
                withoutAnimation { state.wrappedValue.isCoverPresented = true }
            }
        } else if state.wrappedValue.isCoverPresented {
            withAnimation(Constants.dismissAnimation) {
                state.wrappedValue.isCardShown = false
            } completion: {
                guard !state.wrappedValue.isCardShown else { return }
                withoutAnimation { state.wrappedValue.isCoverPresented = false }
            }
        }
    }

    @MainActor
    private static func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

private extension Binding where Value == DSCardSheetState {
    /// The cover's own binding. A view inside calling `dismiss()` removes the cover directly;
    /// mirror that back to the caller's binding so the two never disagree.
    func coverBinding(onSystemDismiss: @escaping () -> Void) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.isCoverPresented },
            set: { isPresented in
                wrappedValue.isCoverPresented = isPresented
                if !isPresented {
                    wrappedValue.isCardShown = false
                    onSystemDismiss()
                }
            }
        )
    }
}

private struct DSCardSheetHost<CardContent: View>: View {
    @Binding var isCardShown: Bool
    let onBackgroundTap: () -> Void
    @ViewBuilder let content: () -> CardContent

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .opacity(isCardShown ? Constants.dimOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
                .accessibilityHidden(true)

            if isCardShown {
                content()
                    .environment(\.isDSCardSheet, true)
                    .frame(maxWidth: .sheetCardMaxWidth)
                    .clipShape(RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous))
                    .padding(Constants.cardMargin)
                    .transition(.move(edge: .bottom))
            }
        }
        .accessibilityAction(.escape, onBackgroundTap)
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(Constants.presentAnimation) { isCardShown = true }
        }
    }
}
