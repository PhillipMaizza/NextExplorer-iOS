import SwiftUI

/// Central catalog of the app's SF Symbols — one name per icon, spelled once, so call
/// sites never type a raw `Image(systemName:)` string.
public enum IconKit {
    public static let checkmark = Image(systemName: "checkmark")
    public static let xmark = Image(systemName: "xmark")
    public static let chevronLeft = Image(systemName: "chevron.left")
    public static let envelope = Image(systemName: "envelope")
    public static let lock = Image(systemName: "lock")
    public static let eye = Image(systemName: "eye")
    public static let eyeSlash = Image(systemName: "eye.slash")
    public static let key = Image(systemName: "key")
    public static let person = Image(systemName: "person")
    public static let logo = Image("logo", bundle: .module)
}
