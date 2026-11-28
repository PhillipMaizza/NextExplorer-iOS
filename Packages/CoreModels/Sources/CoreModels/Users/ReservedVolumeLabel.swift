import Foundation

public enum ReservedVolumeLabel: String, CaseIterable, Sendable {
    case personal
    case share
    case volumes

    public static func contains(_ label: String) -> Bool {
        Self(rawValue: label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) != nil
    }
}
