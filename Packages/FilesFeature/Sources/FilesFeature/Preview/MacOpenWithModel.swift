#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    import Localization
    import PDFKit
    import SwiftUI
    import UniformTypeIdentifiers

    private enum Metrics {
        static let appIconSize: CGFloat = 16
        /// "View as Text" is for a quick look at the bytes, not for loading a disk image into memory.
        static let rawTextByteLimit = 2 * 1024 * 1024
    }

    struct MacOpenWithApp: Identifiable {
        let url: URL
        let name: String
        let icon: Image
        var id: URL {
            url
        }

        @MainActor
        static func apps(forFileNamed fileName: String) -> (preferred: MacOpenWithApp?, all: [MacOpenWithApp]) {
            let type = UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .data
            let workspace = NSWorkspace.shared
            let all = workspace.urlsForApplications(toOpen: type).map(app(at:))
            return (workspace.urlForApplication(toOpen: type).map(app(at:)), all)
        }

        @MainActor
        private static func app(at url: URL) -> MacOpenWithApp {
            let name = FileManager.default.displayName(atPath: url.path)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            // Menu sized, like the app icons in Finder's Open With menu.
            icon.size = NSSize(width: Metrics.appIconSize, height: Metrics.appIconSize)
            return MacOpenWithApp(
                url: url,
                name: (name as NSString).deletingPathExtension,
                icon: Image(nsImage: icon)
            )
        }
    }

    /// What the Mac can print directly, judged from the file's type.
    enum MacPrintKind {
        case pdf, image, text

        init?(fileName: String) {
            guard let type = UTType(filenameExtension: (fileName as NSString).pathExtension) else { return nil }
            if type.conforms(to: .pdf) {
                self = .pdf
            } else if type.conforms(to: .image) {
                self = .image
            } else if type.conforms(to: .text) || type.conforms(to: .sourceCode) {
                self = .text
            } else {
                return nil
            }
        }
    }

    /// Whether "View as Text" makes sense for a file: a text or source type, or a file with no
    /// extension at all (README, Makefile, Dockerfile), which is almost always text.
    enum MacRawTextSupport {
        static func applies(toFileNamed fileName: String) -> Bool {
            let pathExtension = (fileName as NSString).pathExtension
            guard !pathExtension.isEmpty else { return true }
            guard let type = UTType(filenameExtension: pathExtension) else { return false }
            return type.conforms(to: .text) || type.conforms(to: .sourceCode)
        }
    }

    /// ⌘P for the preview on screen, published by its Open With menu.
    public struct PrintPreviewAction {
        let perform: () -> Void

        public func callAsFunction() {
            perform()
        }
    }

    public extension FocusedValues {
        @Entry var printPreview: PrintPreviewAction?
    }

    /// Carries a parsed PDF back from the detached load; only touched on the main actor after.
    private struct PDFBox: @unchecked Sendable {
        let document: PDFDocument
    }

    struct RawTextDocument: Identifiable {
        let id = UUID()
        let name: String
        let text: String
    }

    /// Resolves the previewed file to a local copy (downloading a server file into the cache
    /// first), then hands it to another app or reads it as text.
    @MainActor
    @Observable
    final class MacOpenWithModel {
        let source: SystemShareSource
        var isWorking = false
        var errorMessage: String?
        var rawText: RawTextDocument?
        /// Reports a failure where nothing observes `errorMessage`, as from a context menu.
        @ObservationIgnored private let onFailure: ((String) -> Void)?

        @ObservationIgnored @Dependency(\.filesClient) private var filesClient

        init(source: SystemShareSource, onFailure: ((String) -> Void)? = nil) {
            self.source = source
            self.onFailure = onFailure
        }

        /// Launch Services lookups load every candidate app's icon, so they run once per preview
        /// rather than on every render of the menu.
        @ObservationIgnored lazy var apps: (preferred: MacOpenWithApp?, all: [MacOpenWithApp])? =
            fileName.map { MacOpenWithApp.apps(forFileNamed: $0) }

        var canViewAsText: Bool {
            fileName.map(MacRawTextSupport.applies(toFileNamed:)) ?? false
        }

        var fileName: String? {
            switch source {
            case let .remote(item, _): item.name
            case let .local(url): url?.lastPathComponent
            case .unavailable: nil
            }
        }

        func open(with app: MacOpenWithApp?) {
            run { url in
                if let app {
                    _ = try await NSWorkspace.shared.open([url], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
                } else if !NSWorkspace.shared.open(url) {
                    throw CocoaError(.fileReadUnknown)
                }
            }
        }

        func viewAsText() {
            run { [weak self] url in
                let text = try await MacOpenWithModel.readText(at: url)
                self?.rawText = RawTextDocument(name: url.lastPathComponent, text: text)
            }
        }

        var printKind: MacPrintKind? {
            fileName.flatMap(MacPrintKind.init(fileName:))
        }

        /// Loads the file off the main actor, then shows the system print panel as a sheet.
        func print() {
            guard let kind = printKind else { return }
            run { url in
                let printInfo = NSPrintInfo.shared
                let operation: NSPrintOperation
                switch kind {
                case .pdf:
                    let box = try await Task.detached(priority: .userInitiated) {
                        guard let document = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
                        return PDFBox(document: document)
                    }.value
                    guard let pdfOperation = box.document.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true) else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    operation = pdfOperation
                case .image:
                    let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                    guard let image = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                    let imageView = NSImageView(frame: NSRect(origin: .zero, size: printInfo.imageablePageBounds.size))
                    imageView.image = image
                    imageView.imageScaling = .scaleProportionallyUpOrDown
                    operation = NSPrintOperation(view: imageView, printInfo: printInfo)
                case .text:
                    let text = try await Self.readText(at: url)
                    let textView = NSTextView(frame: NSRect(origin: .zero, size: printInfo.imageablePageBounds.size))
                    textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                    textView.string = text
                    // Sized to the whole document so the print operation paginates all of it.
                    textView.isVerticallyResizable = true
                    textView.sizeToFit()
                    operation = NSPrintOperation(view: textView, printInfo: printInfo)
                }
                if let window = NSApp.keyWindow {
                    operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                } else {
                    operation.run()
                }
            }
        }

        private static func readText(at url: URL) async throws -> String {
            try await Task.detached(priority: .userInitiated) {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: Metrics.rawTextByteLimit) ?? Data()
                return String(decoding: data, as: UTF8.self)
            }.value
        }

        private func run(_ work: @escaping @MainActor (URL) async throws -> Void) {
            guard !isWorking else { return }
            isWorking = true
            errorMessage = nil
            Task {
                defer { isWorking = false }
                do {
                    try await work(localURL())
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = L10n.OpenWith.failed
                    onFailure?(L10n.OpenWith.failed)
                }
            }
        }

        private func localURL() async throws -> URL {
            switch source {
            case let .local(url):
                guard let url else { throw CocoaError(.fileNoSuchFile) }
                return url
            case let .remote(item, serverURL):
                return try await filesClient.downloadRawFile(serverURL, item)
            case .unavailable:
                throw CocoaError(.fileNoSuchFile)
            }
        }
    }
#endif
