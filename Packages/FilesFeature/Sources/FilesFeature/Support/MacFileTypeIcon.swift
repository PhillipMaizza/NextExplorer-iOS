#if os(macOS)
    import AppKit
    import UniformTypeIdentifiers

    /// Finder's icon for a file name's type. An `NSWorkspace` icon lookup goes to Launch Services
    /// and table rows rebuild often, so each type's icon is loaded once per launch.
    @MainActor
    enum MacFileTypeIcon {
        private static var cache: [String: NSImage] = [:]

        static func image(forFileName name: String) -> NSImage {
            let pathExtension = (name as NSString).pathExtension.lowercased()
            if let cached = cache[pathExtension] {
                return cached
            }
            let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: pathExtension) ?? .data)
            cache[pathExtension] = icon
            return icon
        }
    }
#endif
