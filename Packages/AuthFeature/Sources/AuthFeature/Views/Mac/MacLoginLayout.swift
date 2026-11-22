#if os(macOS)
    import ComposableArchitecture
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let windowPadding: CGFloat = .space16
        static let cardPadding: CGFloat = .size40
        static let contentMaxWidth: CGFloat = MacFormSheetMetrics.width
    }

    struct MacLoginLayout<Pages: View>: View {
        let store: StoreOf<LoginFormFeature>
        let hasStepsSidebar: Bool
        @ViewBuilder let pages: () -> Pages

        var body: some View {
            HStack(spacing: .zero) {
                if hasStepsSidebar {
                    MacLoginSidebar(store: store)
                }
                surface(
                    VStack(spacing: .zero) {
                        pages()
                            .defaultScrollAnchor(.center)
                            .frame(maxWidth: Constants.contentMaxWidth)
                            .padding(.horizontal, Constants.cardPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if !hasStepsSidebar {
                            MacLoginFooterLinks(store: store)
                                .padding(.horizontal, Constants.cardPadding)
                                .padding(.bottom, .space16)
                        }
                    }
                )
            }
            .ignoresSafeArea(edges: hasStepsSidebar ? .top : [])
            .background((hasStepsSidebar ? Color.macChrome : .macCard).ignoresSafeArea())
            .toolbar(removing: .title)
            .toolbarBackground(.hidden, for: .windowToolbar)
        }

        @ViewBuilder
        private func surface(_ content: some View) -> some View {
            if hasStepsSidebar {
                content
                    .macCard()
                    .padding(Constants.windowPadding)
            } else {
                content
            }
        }
    }

    struct MacLoginPageHeader: View {
        let host: String
        let title: String?
        let onBack: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                HStack(spacing: .space8) {
                    Button(action: onBack) {
                        IconKit.back
                            .resizable()
                            .scaledToFit()
                            .bold()
                            .frame(width: .iconXSmall, height: .iconXSmall)
                            .frame(width: .size24, height: .size24)
                            .background(Circle().fill(Color.macSegment))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabelWithTooltip(L10n.Common.back)
                    .keyboardShortcut(.cancelAction)
                    Text(host)
                        .type(.body3(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.leading, .space4)
                .padding(.trailing, .space12)
                .frame(height: .size32)
                .background(Capsule().fill(Color.macRow))
                if let title {
                    Text(title)
                        .type(.headline1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    #Preview("Header") {
        MacLoginPageHeader(host: "nextexplorer.example.com", title: L10n.Login.submit, onBack: {})
            .padding(.size40)
            .frame(width: 520)
            .macCard()
    }
#endif
