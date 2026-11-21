import CoreModels
import Foundation
import Localization

/// What a support message needs to reproduce a problem: the app, the device and the system. Nothing
/// about the account or the server.
enum AppDiagnostics {
    private static let missingValue = "-"

    static var appVersion: String {
        Bundle.main.marketingVersion ?? missingValue
    }

    private static var build: String {
        Bundle.main.buildNumber ?? missingValue
    }

    static var versionText: String {
        L10n.Settings.appVersion(appVersion, build)
    }

    /// The hardware identifier, such as `Mac15,3`.
    private static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return text(model)
    }

    private static var chip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return text(brand)
    }

    /// A sysctl string: its bytes up to the null terminator.
    private static func text(_ bytes: [CChar]) -> String {
        String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static var memoryGigabytes: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    private static let separator = String(repeating: "_", count: 40)

    /// The block under the user's own text. The marker lines tell them to leave it as it is.
    static var summary: String {
        [
            separator,
            "DO NOT REMOVE THESE LINES",
            separator,
            "App: NextExplorer v\(appVersion) (\(build))",
            "Device: \(deviceModel), \(chip), \(memoryGigabytes) GB",
            "System: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Language: \(Locale.preferredLanguages.first ?? "?")",
            "Region: \(Locale.current.region?.identifier ?? "?")",
            separator,
        ].joined(separator: "\n")
    }
}
