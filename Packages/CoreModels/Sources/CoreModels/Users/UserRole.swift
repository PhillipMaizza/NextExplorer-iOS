import Foundation

/// Role names as the backend stores them in `user.roles`. `admin` is the only one the
/// server actually grants; everything else is "no role".
public enum UserRole {
    public static let admin = "admin"
}
