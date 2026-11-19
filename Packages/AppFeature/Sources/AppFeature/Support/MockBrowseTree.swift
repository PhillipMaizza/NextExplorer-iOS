#if DEBUG
    import CoreModels
    import Foundation

    /// The UI tests' file world: a real tree holding every kind of file the app treats apart
    /// (images, raw, video, audio, office, PDF, web, archives, code, unknown kinds), names that
    /// are long or accented, sizes from zero bytes to gigabytes, dates from minutes ago to years
    /// back or unknown, an empty folder, a deep chain, a folder long enough to scroll and a read
    /// only one. Dates count back from the launch so "today" and "yesterday" always hold.
    enum MockBrowseTree {
        typealias Folder = UITestFixture.Folder
        typealias Series = UITestFixture.Series

        enum Age {
            static let minute: TimeInterval = 60
            static let hour: TimeInterval = 3600
            static let day: TimeInterval = 86400
            static let week: TimeInterval = 7 * day
            static let month: TimeInterval = 30 * day
            static let year: TimeInterval = 365 * day
        }

        enum Size {
            static let kilobyte: Int64 = 1024
            static let megabyte: Int64 = 1024 * kilobyte
            static let gigabyte: Int64 = 1024 * megabyte
        }

        /// Every folder's children by folder path ("" is the root), as the server would list them.
        static func seed(now: Date) -> [String: [FileItem]] {
            var tree: [String: [FileItem]] = [:]
            func add(_ folder: Folder?, _ entries: [Entry]) {
                let path = folder?.path ?? ""
                tree[path] = entries.map { $0.item(in: path, now: now) }
            }

            add(nil, [
                .folder(.photos, age: 2 * Age.day),
                .folder(.documents, age: 3 * Age.hour),
                .folder(.media, age: 2 * Age.month),
                .folder(.projects, age: Age.week),
                .folder(.teamLibrary, age: 5 * Age.month),
                .file(.vacation, 2_400_000, age: Age.day, thumbnail: true),
                .file(.notes, Size.kilobyte, age: 20 * Age.minute),
                .file(.welcome, 180 * Size.kilobyte, age: Age.year),
            ])
            add(.documents, [
                .folder(.invoices, age: Age.month),
                .file(.notes, 3 * Size.kilobyte, age: 2 * Age.hour),
                .file(.quarterlyReport, 12 * Size.kilobyte, age: Age.week),
                .file(.meetingNotes, 6 * Size.kilobyte, age: Age.day),
                .file(.beach, 3 * Size.megabyte, age: 3 * Age.month, thumbnail: true),
                .file(.proposal, 220 * Size.kilobyte, age: 4 * Age.day),
                .file(.budget, 88 * Size.kilobyte, age: 6 * Age.day),
                .file(.roadmap, 4 * Size.megabyte, age: 2 * Age.week),
                .file(.contract, 640 * Size.kilobyte, age: 8 * Age.month),
                .file(.resume, 95 * Size.kilobyte, age: 2 * Age.year),
                .file(.teamSheet, 180, age: Age.week),
                .file(.logo, 9 * Size.kilobyte, age: Age.month),
                .file(.empty, 0, age: 5 * Age.minute),
                .file(.export, 50 * Size.megabyte, age: nil),
            ])
            add(.invoices, [.folder(.invoices2025, age: 4 * Age.month), .folder(.invoices2026, age: Age.month)])
            add(.invoices2025, Series.invoiceMonths2025.map {
                .generated(
                    Series.invoice(.invoices2025, month: $0),
                    70 * Size.kilobyte,
                    age: Age.year - Double($0) * Age.month
                )
            })
            add(.invoices2026, Series.invoiceMonths2026.map {
                .generated(
                    Series.invoice(.invoices2026, month: $0),
                    72 * Size.kilobyte,
                    age: Double(4 - $0) * Age.month
                )
            })
            add(.photos, [
                .folder(.cameraRoll, age: Age.hour),
                .folder(.photos2024, age: Age.year),
                .file(.sunset, 5 * Size.megabyte, age: 3 * Age.day, thumbnail: true),
                .file(.portrait, 24 * Size.megabyte, age: 10 * Age.day, thumbnail: true),
                .file(.birthday, 310 * Size.megabyte, age: 2 * Age.month, thumbnail: true),
            ])
            add(.cameraRoll, (1 ... Series.cameraRollCount).map {
                .generated(
                    Series.cameraRollPhoto($0),
                    3 * Size.megabyte,
                    age: Double(Series.cameraRollCount - $0) * Age.hour,
                    thumbnail: true
                )
            })
            add(.photos2024, [
                .file(.beachDay, 4 * Size.megabyte, age: Age.year + Age.month, thumbnail: true),
                .file(.snow, 2 * Size.megabyte, age: Age.year + 3 * Age.month, thumbnail: true),
            ])
            add(.media, [
                .file(.podcast, 48 * Size.megabyte, age: Age.week),
                .file(.song, 7 * Size.megabyte, age: 6 * Age.month),
                .file(.concert, 2 * Size.gigabyte, age: Age.year),
                .file(.trailer, 90 * Size.megabyte, age: 3 * Age.week, thumbnail: true),
            ])
            add(.projects, [
                .folder(.drafts, age: Age.day),
                .folder(.website, age: 2 * Age.week),
                .folder(.clients, age: Age.month),
                .file(.siteBackup, 120 * Size.megabyte, age: 2 * Age.month),
                .file(.tools, 30 * Size.megabyte, age: 7 * Age.month),
                .file(.archiveNotes, 2 * Size.kilobyte, age: 3 * Age.month),
            ])
            add(.drafts, [])
            add(.website, [
                .file(.index, 4 * Size.kilobyte, age: 2 * Age.week),
                .file(.styles, 2 * Size.kilobyte, age: 2 * Age.week),
                .file(.script, 11 * Size.kilobyte, age: 2 * Age.week),
                .file(.config, 900, age: 3 * Age.week),
                .file(.readme, 3 * Size.kilobyte, age: 3 * Age.week),
            ])
            add(.clients, [.folder(.acme, age: Age.month)])
            add(.acme, [.folder(.launch, age: Age.month)])
            add(.launch, [.folder(.kickoff, age: Age.month)])
            add(.kickoff, [.file(.agenda, 60 * Size.kilobyte, age: Age.week)])
            add(.teamLibrary, [
                .file(.handbook, 2 * Size.megabyte, age: 5 * Age.month),
                .file(.brandGuide, 14 * Size.megabyte, age: 9 * Age.month),
            ])
            return tree
        }

        /// What the account may do in `path`: everything, except read and download in the team library.
        static func access(for path: String) -> FileAccess {
            let library = Folder.teamLibrary.path
            let isReadOnly = path == library || path.hasPrefix("\(library)/")
            return FileAccess(
                canRead: true,
                canWrite: !isReadOnly,
                canUpload: !isReadOnly,
                canDelete: !isReadOnly,
                canShare: !isReadOnly,
                canDownload: true
            )
        }
    }

    /// One listed item before it knows its folder and the launch time.
    struct Entry {
        let name: String
        let size: Int64
        let age: TimeInterval?
        let isFolder: Bool
        let hasThumbnail: Bool

        static func folder(_ folder: UITestFixture.Folder, age: TimeInterval) -> Entry {
            Entry(name: folder.name, size: 0, age: age, isFolder: true, hasThumbnail: false)
        }

        /// A named file whose kind is its extension; `age` nil is a date the server could not read.
        static func file(
            _ file: UITestFixture.File,
            _ size: Int64,
            age: TimeInterval?,
            thumbnail: Bool = false
        ) -> Entry {
            generated(file.name, size, age: age, thumbnail: thumbnail)
        }

        /// A file from a numbered series.
        static func generated(_ name: String, _ size: Int64, age: TimeInterval?, thumbnail: Bool = false) -> Entry {
            Entry(name: name, size: size, age: age, isFolder: false, hasThumbnail: thumbnail)
        }

        func item(in path: String, now: Date) -> FileItem {
            let suffix = (name as NSString).pathExtension.lowercased()
            return FileItem(
                name: name,
                path: path,
                dateModified: age.map { now.addingTimeInterval(-$0) } ?? FileItem.unknownDate,
                size: size,
                kind: isFolder ? FileItem.directoryKind : (suffix.isEmpty ? FileItem.unknownKind : suffix),
                supportsThumbnail: hasThumbnail
            )
        }
    }
#endif
