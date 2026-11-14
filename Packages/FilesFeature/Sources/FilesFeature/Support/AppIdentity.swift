import Foundation

/// The app's own name, as the bundle shows it on the Home Screen or in the Dock. A product name, so it
/// is never translated.
enum AppIdentity {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ""
    }
}
