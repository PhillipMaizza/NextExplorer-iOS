import Foundation

/// Files another app handed over through "Open in NextExplorer" in its share sheet, waiting for a
/// signed in tab shell to upload them. `AppFeature` appends as they arrive; `MainTabFeature` drains
/// it when its shell mounts and on `sharedFilesArrived`. These are the user's own local documents,
/// not server data, so a session boundary leaves them queued for whichever account signs in.
public enum SharedFileInbox {
    public static let sharedKey = "sharedFileInbox"
}
