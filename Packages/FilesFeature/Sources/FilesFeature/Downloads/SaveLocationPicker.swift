import ComposableArchitecture
import DependenciesMacros
import Foundation
#if os(macOS)
    import AppKit
#endif

/// Where a Mac download goes: the user picks it in a system save panel (one file) or open
/// panel (a folder for several), the way every Mac app saves. `nil` means cancelled. iOS keeps
/// its own Files based download flow and never calls this.
@DependencyClient
public struct SaveLocationPicker: Sendable {
    public var chooseFile: @Sendable (_ suggestedName: String) async -> URL? = { _ in nil }
    public var chooseFolder: @Sendable () async -> URL? = { nil }
}

extension SaveLocationPicker: DependencyKey {
    public static let testValue = SaveLocationPicker()

    #if os(macOS)
        public static let liveValue = SaveLocationPicker(
            chooseFile: { suggestedName in
                await MainActor.run {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = suggestedName
                    panel.canCreateDirectories = true
                    panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    return panel
                }.present()
            },
            chooseFolder: {
                await MainActor.run {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    return panel
                }.present()
            }
        )
    #else
        public static let liveValue = SaveLocationPicker()
    #endif
}

public extension DependencyValues {
    var saveLocationPicker: SaveLocationPicker {
        get { self[SaveLocationPicker.self] }
        set { self[SaveLocationPicker.self] = newValue }
    }
}

#if os(macOS)
    private extension NSSavePanel {
        /// A sheet on the front window when there is one, otherwise a standalone panel.
        @MainActor
        func present() async -> URL? {
            let response = if let window = NSApp.keyWindow {
                await beginSheetModal(for: window)
            } else {
                runModal()
            }
            return response == .OK ? url : nil
        }
    }

    /// Copies a finished download to where the user chose. The save panel already confirmed any
    /// overwrite, so an existing file there is replaced.
    enum MacDownloadSaving {
        static func copy(_ source: URL, to destination: URL) throws {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        /// A name in `folder` that doesn't clash with anything already there ("name 2.ext").
        static func uniqueDestination(in folder: URL, fileName: String) -> URL {
            let base = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            var candidate = folder.appendingPathComponent(fileName)
            var index = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
                candidate = folder.appendingPathComponent(name)
                index += 1
            }
            return candidate
        }
    }
#endif
