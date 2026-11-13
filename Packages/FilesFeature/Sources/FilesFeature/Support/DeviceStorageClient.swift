import Dependencies
import Foundation

/// How much room the device has for files the app keeps, so a download never starts that cannot finish.
struct DeviceStorageClient: Sendable {
    /// What the OS counts as available for important storage; unknown reads as unlimited so the guard
    /// never blocks a download it cannot size.
    var freeBytes: @Sendable () -> Int64
}

extension DeviceStorageClient: DependencyKey {
    static let liveValue = DeviceStorageClient(freeBytes: {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    })

    static let testValue = DeviceStorageClient(freeBytes: { .max })
}

extension DependencyValues {
    var deviceStorage: DeviceStorageClient {
        get { self[DeviceStorageClient.self] }
        set { self[DeviceStorageClient.self] = newValue }
    }
}
