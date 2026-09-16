import AuthenticationServices
import Foundation
import UIKit

/// Runs the OIDC leg in an `ASWebAuthenticationSession` — the only iOS web context that
/// supports passkeys/WebAuthn (system credential store) while still handing the app the
/// final custom scheme callback URL. A plain `WKWebView` can capture cookies but blocks
/// passkeys; Safari/`SFSafariViewController` supports passkeys but never returns control,
/// which is why the bridge exists at all.
@MainActor
final class OIDCWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
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
            }
        }
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
