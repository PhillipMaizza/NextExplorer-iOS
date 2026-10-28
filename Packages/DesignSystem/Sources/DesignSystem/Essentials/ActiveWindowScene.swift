import UIKit

/// The window scene the app is drawing into right now. Replaces `UIScreen.main`, which is
/// deprecated since iOS 16 and on a foldable can name a display the app is not on: iPhone Duo
/// moves the scene between its outer and inner panels, each with its own size.
@MainActor
public enum ActiveWindowScene {
    public static var current: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Bounds of the key window, falling back to the scene's screen before a window is key.
    public static var bounds: CGRect? {
        guard let scene = current else { return nil }
        return scene.keyWindow?.bounds ?? scene.screen.bounds
    }
}
