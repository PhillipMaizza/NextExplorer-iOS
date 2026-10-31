import AuthenticationServices
import Foundation
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Runs the OIDC leg in an `ASWebAuthenticationSession`: the only iOS web context that
/// supports passkeys/WebAuthn (system credential store) while still handing the app the
/// final custom scheme callback URL. A plain `WKWebView` can capture cookies but blocks
/// passkeys; Safari/`SFSafariViewController` supports passkeys but never returns control,
/// which is why the bridge exists at all.
@MainActor
final class OIDCWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// A cancelled sign in (the login screen closed or the task torn down) cancels the web
    /// session, which answers the continuation with `canceledLogin`; a finished session is let go.
    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        defer { session = nil }
        return try await withTaskCancellationHandler {
            try await start(url: url, callbackURLScheme: callbackURLScheme)
        } onCancel: {
            Task { @MainActor [weak self] in self?.session?.cancel() }
        }
    }

    private func start(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { @Sendable callbackURL, error in
                // Nonisolated on purpose: the Mac calls this on a background queue, where a
                // main actor closure (inferred from the class) traps the isolation check.
                if let error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin
                    {
                        continuation.resume(throwing: AuthClientError.oidcCancelled)
                    } else {
                        continuation.resume(throwing: AuthClientError.oidcFailed(String(describing: error)))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthClientError.oidcFailed("no callback URL"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Share the system browser session so an existing IdP/SSO sign-in (and its passkey
            // association) is reused rather than forcing a fresh authentication every time.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AuthClientError.oidcFailed("could not start web session"))
            } else if Task.isCancelled {
                // Cancelled before the session existed, so the handler had nothing to cancel.
                session.cancel()
            }
        }
    }

    /// Anchors on the foreground scene's key window. A scene less `UIWindow()` is deprecated
    /// since iOS 26, so it is only the last resort when no scene is connected at all.
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
            return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        #else
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
                return ASPresentationAnchor()
            }
            return scene.keyWindow ?? UIWindow(windowScene: scene)
        #endif
    }
}
