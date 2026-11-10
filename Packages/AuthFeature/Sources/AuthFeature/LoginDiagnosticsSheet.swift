import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// Appears once something on the sign in screen has failed, and opens the log of what the server
/// answered so it can be copied or shared with the developer.
struct LoginDiagnosticsButton: View {
    /// Plain values rather than the log itself: the log compares equal whatever it holds, so
    /// SwiftUI would see an unchanged input and never redraw the button once a failure lands.
    let hasProblem: Bool
    let text: String
    @State private var isPresented = false

    init(diagnostics: LoginDiagnostics) {
        hasProblem = diagnostics.hasProblem
        text = diagnostics.hasProblem ? diagnostics.rendered(header: LoginDiagnostics.environmentHeader()) : ""
    }

    var body: some View {
        if hasProblem {
            DSButton(L10n.Login.diagnosticsButton, icon: IconKit.document, style: .ghost, size: .small) {
                isPresented = true
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Login.diagnosticsButton)
            .dsSheet(isPresented: $isPresented) {
                LoginDiagnosticsSheet(text: text, onClose: { isPresented = false })
            }
        }
    }
}

struct LoginDiagnosticsSheet: View {
    let text: String
    let onClose: () -> Void

    private enum Constants {
        static let maxHeightFraction: CGFloat = 0.9
    }

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Constants.maxHeightFraction) {
            VStack(alignment: .leading, spacing: .space24) {
                DSSheetHeader(
                    icon: IconKit.document,
                    title: L10n.Login.diagnosticsTitle,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: onClose
                )
                Text(L10n.Login.diagnosticsIntro)
                    .type(.body2(.regular), style: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.primaryDS)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsCard()
            }
            .padding(.horizontal, .space24)
            .padding(.vertical, .space24)
        } footer: {
            DSSheetFooter {
                HStack(spacing: .space12) {
                    DSButton(L10n.Common.copy, icon: IconKit.copy, style: .outline) {
                        PlatformPasteboard.copy(text)
                    }
                    ShareLink(item: text) {
                        Text(L10n.Common.share)
                            .type(.label3)
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: .size48)
                            .background(Color.accent, in: RoundedRectangle(cornerRadius: .radiusControl, style: .continuous))
                    }
                }
            }
        }
    }
}

#if DEBUG
    private enum PreviewConstants {
        static let header = ["NextExplorer 1.1.4 (1)", "OS: Version 27.0"]
    }

    private var previewDiagnostics: LoginDiagnostics {
        var diagnostics = LoginDiagnostics()
        diagnostics.record("connecting: https, default port", at: .distantPast)
        diagnostics.record("server status: password sign in on, single sign on off, redirected to https false", at: .distantPast)
        diagnostics.record("sign in: rejected: server answered 401, no account matches that name and password", isProblem: true, at: .distantPast)
        return diagnostics
    }

    #Preview("Sheet") {
        Color.backgroundPrimary
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                LoginDiagnosticsSheet(text: previewDiagnostics.rendered(header: PreviewConstants.header), onClose: {})
            }
    }

    #Preview("Sheet, empty log") {
        Color.backgroundPrimary
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                LoginDiagnosticsSheet(text: LoginDiagnostics().rendered(header: PreviewConstants.header), onClose: {})
            }
    }

    #Preview("Button, after a failure") {
        LoginDiagnosticsButton(diagnostics: previewDiagnostics)
            .padding(.space16)
    }

    #Preview("Button, nothing failed (hidden)") {
        LoginDiagnosticsButton(diagnostics: LoginDiagnostics())
            .padding(.space16)
    }
#endif
