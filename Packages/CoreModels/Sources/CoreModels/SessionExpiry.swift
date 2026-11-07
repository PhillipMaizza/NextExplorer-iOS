import Foundation

public enum SessionExpiry {
    /// Set to `true` by `apiResult` when an authenticated endpoint answers 401. `AppFeature`
    /// watches it, drops to the login screen, clears the session, then resets the flag. An
    /// in memory flag rather than delegate plumbing, since every effect already routes its
    /// errors through `apiResult`.
    public static let sharedKey = "sessionDidExpire"
}
