#if DEBUG
    import CoreModels
    import FilesClient
    import Foundation
    #if os(iOS)
        import UIKit
    #endif

    extension UITestSupport {
        /// The `gallery` scenario's folder: one file per gallery page kind, named so they list in
        /// this order, and a subfolder the gallery skips but a move can target. Mirrors
        /// `GalleryUITests.Fixture` in the test target.
        static let galleryItems: [FileItem] = [
            FileItem(name: "Projects", path: "", dateModified: Date(), size: 0, kind: FileItem.directoryKind),
            FileItem(name: "archive.zip", path: "", dateModified: Date(), size: 4_096, kind: "zip"),
            FileItem(name: "clip.mp4", path: "", dateModified: Date(), size: 8_192, kind: "mp4"),
            FileItem(name: "installer.dmg", path: "", dateModified: Date(), size: 16_384, kind: "dmg"),
            FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 1_024, kind: "txt"),
            FileItem(name: "report.pdf", path: "", dateModified: Date(), size: 2_048, kind: "pdf"),
            FileItem(name: "sunset.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg"),
            FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg"),
        ]

        /// What every text file reads back in the `gallery` scenario. Its first line is what a UI
        /// test looks for (`GalleryUITests.Fixture.notesText`).
        static let galleryNotesText = """
        Gallery notes

        This text file sits in the gallery between the installer and the report.
        Swipe left for the PDF, then the photos; swipe right for the files before.
        Tap Edit to change it in the editor, then Close to come back here.
        """

        /// Real content for the gallery's pages: rendered photos and a two page PDF, written once to
        /// a temporary folder, so a run shows what the gallery does with actual files.
        static func installGalleryFiles(into client: inout FilesClient) {
            client.fetchTextContent = { _, _ in galleryNotesText }
            #if os(iOS)
                client.previewFile = { _, item in try galleryFile(for: item) }
                client.previewFileLowPriority = { _, item in try galleryFile(for: item) }
            #endif
        }

        #if os(iOS)
            private static let galleryFolder = FileManager.default.temporaryDirectory
                .appendingPathComponent("UITestGallery", isDirectory: true)

            private static func galleryFile(for item: FileItem) throws -> URL {
                try FileManager.default.createDirectory(at: galleryFolder, withIntermediateDirectories: true)
                let url = galleryFolder.appendingPathComponent(item.name)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
                let data: Data = switch item.kind.lowercased() {
                case "pdf": galleryPDF(title: item.name)
                case "jpg", "jpeg", "png": galleryPhoto(named: item.name)
                default: Data()
                }
                try data.write(to: url)
                return url
            }

            /// A landscape picture: a sky gradient, a sun and the file's name.
            private static func galleryPhoto(named name: String) -> Data {
                let size = CGSize(width: 1_600, height: 1_067)
                let isSunset = name.hasPrefix("sunset")
                let top = isSunset ? UIColor.systemIndigo : UIColor.systemTeal
                let bottom = isSunset ? UIColor.systemOrange : UIColor.systemGreen
                let image = UIGraphicsImageRenderer(size: size).image { context in
                    let colors = [top.cgColor, bottom.cgColor] as CFArray
                    if let gradient = CGGradient(
                        colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: colors,
                        locations: nil
                    ) {
                        context.cgContext.drawLinearGradient(
                            gradient,
                            start: .zero,
                            end: CGPoint(x: 0, y: size.height),
                            options: []
                        )
                    }
                    UIColor.systemYellow.setFill()
                    UIBezierPath(ovalIn: CGRect(x: 1_050, y: 220, width: 280, height: 280)).fill()
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 110),
                        .foregroundColor: UIColor.white,
                    ]
                    (name as NSString).draw(at: CGPoint(x: 90, y: 800), withAttributes: attributes)
                }
                return image.jpegData(compressionQuality: 0.85) ?? Data()
            }

            /// A two page report with a title and a few paragraphs on each page.
            private static func galleryPDF(title: String) -> Data {
                let page = CGRect(x: 0, y: 0, width: 612, height: 792)
                let paragraph = "The gallery pages through every file in a folder. "
                    + "Photos decode in place, documents open in Quick Look, text reads back with highlighting, "
                    + "videos play in their page, and a zip offers to open the archive browser."
                return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
                    for number in 1 ... 2 {
                        context.beginPage()
                        let heading: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 30)]
                        ("\(title) page \(number)" as NSString).draw(at: CGPoint(x: 56, y: 64), withAttributes: heading)
                        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16)]
                        let text = Array(repeating: paragraph, count: 4).joined(separator: "\n\n")
                        (text as NSString).draw(in: page.insetBy(dx: 56, dy: 130), withAttributes: body)
                    }
                }
            }
        #endif
    }
#endif
