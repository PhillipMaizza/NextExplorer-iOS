#if os(macOS)
    import SwiftUI

    // Same named stand ins for iOS only SwiftUI API so shared feature views compile on macOS
    // unchanged. Each one is either a no op (the concept does not exist on a Mac) or maps to the
    // closest native macOS equivalent.

    public enum NavigationBarItem {
        public enum TitleDisplayMode {
            case automatic
            case inline
            case large
        }
    }

    public enum TextInputAutocapitalization {
        case never
        case words
        case sentences
        case characters
    }

    public enum UIKeyboardType {
        case `default`
        case URL
        case emailAddress
        case numberPad
        case decimalPad
    }

    public extension View {
        func navigationBarTitleDisplayMode(_: NavigationBarItem.TitleDisplayMode) -> some View {
            self
        }

        func textInputAutocapitalization(_: TextInputAutocapitalization?) -> some View {
            self
        }

        func keyboardType(_: UIKeyboardType) -> some View {
            self
        }

        func statusBarHidden(_: Bool = true) -> some View {
            self
        }

        /// A Mac has no full screen modal; a sheet is the native equivalent.
        func fullScreenCover(
            isPresented: Binding<Bool>,
            onDismiss: (() -> Void)? = nil,
            @ViewBuilder content: @escaping () -> some View
        ) -> some View {
            sheet(isPresented: isPresented, onDismiss: onDismiss) {
                content().frame(minWidth: MacSheetSize.minWidth, minHeight: MacSheetSize.minHeight)
            }
        }

        func fullScreenCover<Item: Identifiable>(
            item: Binding<Item?>,
            onDismiss: (() -> Void)? = nil,
            @ViewBuilder content: @escaping (Item) -> some View
        ) -> some View {
            sheet(item: item, onDismiss: onDismiss) { item in
                content(item).frame(minWidth: MacSheetSize.minWidth, minHeight: MacSheetSize.minHeight)
            }
        }
    }

    private enum MacSheetSize {
        static let minWidth: CGFloat = 720
        static let minHeight: CGFloat = 540
    }

    public extension ToolbarItemPlacement {
        static var topBarLeading: ToolbarItemPlacement {
            .navigation
        }

        static var topBarTrailing: ToolbarItemPlacement {
            .primaryAction
        }

        static var bottomBar: ToolbarItemPlacement {
            .automatic
        }
    }

    public extension ListStyle where Self == InsetListStyle {
        static var insetGrouped: InsetListStyle {
            .inset
        }
    }
#endif
