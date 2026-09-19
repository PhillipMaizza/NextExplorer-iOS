import CoreModels
import CryptoKit
import Foundation
import NetworkClient

extension FilesService {
    static let previewCacheRootDirectory = "PreviewCache"
    static let cacheMetaSidecarName = ".meta"
    static let rawPreviewFileExtension = "jpg"
    /// `previewCacheNamespace` / `rawDownloadCacheNamespace` keep `previewFile`
    /// (`GET /api/preview`) and `downloadRawFile` (`POST /api/download`) from ever sharing a
    /// cache entry for the same item — two different endpoints, nothing guarantees identical
    /// bytes for every kind that uses both (RAW images already diverge one direction).
    static let previewCacheNamespace = "preview"
    static let rawDownloadCacheNamespace = "download"
    /// Flat subdirectory of thumbnail image bytes written by `FilesFeature`'s `ThumbnailCache`
    /// under this same `PreviewCache` root. Kept in sync with `ThumbnailCache`'s own
    /// `previewCacheSubdirectory("thumbnails")`; the two live in different packages, so the name
    /// is duplicated deliberately. Included in eviction so thumbnails (each up to the 32 MB
    /// response cap when `thumbnailURL` falls back to a full preview) can't grow the cache
    /// without bound.
    static let thumbnailCacheSubdirectory = "thumbnails"

    /// Total byte ceiling for the on disk preview + raw download cache. Without it the cache
    /// only ever grows (each previewed/downloaded file is added, never reclaimed) and can fill
    /// the device, since `Library/Caches` is only purged under severe OS storage pressure.
    static let previewCacheMaxBytes: Int64 = 512 * 1024 * 1024

    private static let evictionLock = NSLock()

    /// The on disk cache slot for `item`'s downloaded preview: the directory, the file
    /// itself, and its staleness sidecar. RAW formats always come back as a JPEG stream
    /// (`rawPreviewService`) whatever the original extension, so they're stored with a
    /// matching name or QuickLook's extension-based UTI detection tries to render JPEG bytes
    /// as e.g. `.nef` and fails.
    private func previewCacheSlot(for item: FileItem) -> (directory: URL, fileURL: URL, metaURL: URL) {
        let directory = Self.previewCacheDirectory(for: item, namespace: Self.previewCacheNamespace)
        let safeName = SafeFileName.component(item.name)
        let fileName = item.isRawImage ? "\(safeName).\(Self.rawPreviewFileExtension)" : safeName
        return (
            directory,
            directory.appendingPathComponent(fileName),
            directory.appendingPathComponent(Self.cacheMetaSidecarName)
        )
    }

    /// The already-downloaded preview file for `item`, or `nil` when it isn't cached (or the
    /// cache entry is stale). Pure disk check, no network.
    func cachedPreviewFileURL(item: FileItem) -> URL? {
        let slot = previewCacheSlot(for: item)
        guard FileManager.default.fileExists(atPath: slot.fileURL.path),
              let cachedMeta = try? String(contentsOf: slot.metaURL, encoding: .utf8),
              cachedMeta == Self.cacheMetaValue(for: item)
        else {
            return nil
        }
        return slot.fileURL
    }

    func previewFile(serverURL: URL, item: FileItem) async throws -> URL {
        try await fetchPreviewFile(serverURL: serverURL, item: item, lowPriority: false)
    }

    /// `previewFile` served over the low priority session — for opportunistic fetches (PDF
    /// first page thumbnails) that must not compete with interactive traffic. Same cache
    /// slot, so a later tap-to-open reuses the download and a cache hit here returns with no
    /// network.
    func previewFileLowPriority(serverURL: URL, item: FileItem) async throws -> URL {
        try await fetchPreviewFile(serverURL: serverURL, item: item, lowPriority: true)
    }

    private func fetchPreviewFile(serverURL: URL, item: FileItem, lowPriority: Bool) async throws -> URL {
        // A durable offline pin wins over the ephemeral preview cache: it is the same file, never
        // evicted, and lets the preview open with no network at all.
        if let offline = OfflineCache.localURL(for: item) {
            return offline
        }
        if let cached = cachedPreviewFileURL(item: item) {
            return cached
        }
        guard let url = FilesClient.previewURL(serverURL: serverURL, item: item) else {
            throw FilesClientError.decoding("Could not build preview URL.")
        }
        let slot = previewCacheSlot(for: item)
        let request = Self.makeRequest(url: url, method: .get)
        do {
            return try await downloadToCache(
                request, directory: slot.directory, fileURL: slot.fileURL, metaURL: slot.metaURL,
                item: item, lowPriority: lowPriority
            )
        } catch let error as FilesClientError where error == .offline {
            // Offline and the metadata checked pin missed (e.g. a Favorites direct open seeds a
            // placeholder `FileItem` with no real size/date): serve any pinned copy for this path as
            // a last resort rather than failing. Only when genuinely offline, never masking a real
            // server error or a changed file while online.
            if let fallback = OfflineCache.localURL(forPath: item.id) {
                return fallback
            }
            throw error
        }
    }

    /// `POST /api/download`, confirmed against `backend/src/routes/files/download.js` mounted
    /// at plain `/api` (not `/api/files`) in `backend/src/routes/index.js` — easy to get wrong
    /// by pattern-matching the file's own path (`routes/files/download.js`) instead of its
    /// actual mount point.
    /// unlike `GET /api/preview`, this isn't restricted to `PREVIEWABLE_EXTENSIONS` — a single
    /// non-directory target streams back as the raw file (`res.download`), whatever its kind.
    /// That's what makes client-side archive browsing (`ZIPFoundation`/`Unrar.swift`) possible
    /// at all: the server has no listing-only endpoint, so the whole archive has to come down
    /// first. Reuses `previewFile`'s cache layout (same staleness key) but under its own
    /// `namespace`, so the two endpoints never share a cache slot for the same item.
    func downloadRawFile(serverURL: URL, item: FileItem) async throws -> URL {
        if let offline = OfflineCache.localURL(for: item) {
            return offline
        }
        let directory = Self.previewCacheDirectory(for: item, namespace: Self.rawDownloadCacheNamespace)
        let fileURL = directory.appendingPathComponent(SafeFileName.component(item.name))
        let metaURL = directory.appendingPathComponent(Self.cacheMetaSidecarName)

        if FileManager.default.fileExists(atPath: fileURL.path),
           let cachedMeta = try? String(contentsOf: metaURL, encoding: .utf8),
           cachedMeta == Self.cacheMetaValue(for: item)
        {
            return fileURL
        }

        let url = serverURL.appendingPathComponent(APIPath.download)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(DownloadRawFileBody(path: item.id))
        do {
            return try await downloadToCache(request, directory: directory, fileURL: fileURL, metaURL: metaURL, item: item)
        } catch let error as FilesClientError where error == .offline {
            if let fallback = OfflineCache.localURL(forPath: item.id) {
                return fallback
            }
            throw error
        }
    }

    /// Streams `item`'s verbatim bytes (`POST /api/download`) into the durable offline store so it
    /// opens with no network later. Returns the local file (a cache hit returns with no network).
    ///
    /// Deliberately NOT routed through `downloadCoordinator`: the coordinator runs its work in a
    /// detached task, which severs structured cancellation, so a cancelled offline run (a new download
    /// superseding an `autoSync`, or an explicit cancel) would leave the old transfer running and
    /// collide with the new one. Run directly instead, so cancelling the calling task propagates
    /// straight into `downloadWithProgress` and actually stops the transfer. The coordinator's only
    /// job was collapsing concurrent transfers into the same slot, which never happens here: a cache
    /// hit short circuits, and only one offline run is ever in flight (shared cancel id).
    func offlineDownloadFile(
        serverURL: URL,
        item: FileItem,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        if let existing = OfflineCache.localURL(for: item) {
            return existing
        }
        guard OfflineCache.slot(for: item, create: true) != nil else {
            throw FilesClientError.decoding("Could not open the offline store.")
        }
        let url = serverURL.appendingPathComponent(APIPath.download)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(DownloadRawFileBody(path: item.id))

        let downloadedURL: URL
        let response: HTTPURLResponse
        do {
            (downloadedURL, response) = try await networkClient.downloadWithProgress(request, onProgress)
        } catch {
            throw Self.mapTransportError(error)
        }
        defer { try? FileManager.default.removeItem(at: downloadedURL) }
        try Self.validate(response)
        do {
            return try OfflineCache.store(downloadedURL: downloadedURL, item: item)
        } catch let error as FilesClientError {
            throw error
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// Streams `request`'s response to disk (never buffering it in memory — previews,
    /// downloads and whole archives can be very large) and lands it at `fileURL` with a
    /// staleness sidecar, or returns the existing cache entry untouched. Concurrent calls for
    /// the same `fileURL` share a single download via `downloadCoordinator`.
    private func downloadToCache(
        _ request: URLRequest, directory: URL, fileURL: URL, metaURL: URL, item: FileItem,
        lowPriority: Bool = false
    ) async throws -> URL {
        let networkClient = networkClient
        return try await downloadCoordinator.run(forFileAt: fileURL) {
            let downloadedURL: URL
            let response: HTTPURLResponse
            do {
                (downloadedURL, response) = lowPriority
                    ? try await networkClient.lowPriorityDownload(request)
                    : try await networkClient.download(request)
            } catch {
                throw Self.mapTransportError(error)
            }
            defer { try? FileManager.default.removeItem(at: downloadedURL) }
            try Self.validate(response)

            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: fileURL)
                try FileManager.default.moveItem(at: downloadedURL, to: fileURL)
                try Self.cacheMetaValue(for: item).write(to: metaURL, atomically: true, encoding: .utf8)
                Self.applyCacheProtection(to: fileURL)
                Self.applyCacheProtection(to: metaURL)
                Self.evictPreviewCacheIfNeeded()
                return fileURL
            } catch {
                throw FilesClientError.decoding(error.localizedDescription)
            }
        }
    }

    /// Cached file bytes and directory listings are sensitive (they are the user's files).
    /// `.completeUnlessOpen` keeps them encrypted at rest while still allowing an in flight
    /// preview/download that opened the file before the device locked to finish.
    private static func applyCacheProtection(to url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
        )
    }

    /// Evicts the least recently modified cache slots once the preview/download/thumbnail cache
    /// exceeds `previewCacheMaxBytes`. Runs after each successful download (already an I/O heavy
    /// op) so growth stays bounded within a single long session, not just across relaunches. A
    /// whole item slot (its file and `.meta`, or a single thumbnail file) is removed at once so a
    /// slot is never left half evicted.
    static func evictPreviewCacheIfNeeded() {
        evictionLock.lock()
        defer { evictionLock.unlock() }

        let fileManager = FileManager.default
        guard let cachesDirectory = try? fileManager.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        let root = cachesDirectory.appendingPathComponent(Self.previewCacheRootDirectory, isDirectory: true)

        // A single evictable unit removed atomically: a per item preview/download directory, or
        // a lone thumbnail file. `url` is whatever `removeItem` should delete.
        struct Slot {
            let url: URL
            let modified: Date
            let size: Int64
        }

        var slots: [Slot] = []
        var total: Int64 = 0
        for namespace in [Self.previewCacheNamespace, Self.rawDownloadCacheNamespace] {
            let namespaceRoot = root.appendingPathComponent(namespace, isDirectory: true)
            let slotDirectories = (try? fileManager.contentsOfDirectory(
                at: namespaceRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: []
            )) ?? []
            for slotDirectory in slotDirectories {
                let contents = (try? fileManager.contentsOfDirectory(
                    at: slotDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: []
                )) ?? []
                var slotSize: Int64 = 0
                var modified = Date.distantPast
                for entry in contents {
                    let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    slotSize += Int64(values?.fileSize ?? 0)
                    if let entryModified = values?.contentModificationDate, entryModified > modified {
                        modified = entryModified
                    }
                }
                slots.append(Slot(url: slotDirectory, modified: modified, size: slotSize))
                total += slotSize
            }
        }

        // Thumbnails are flat files (not per item directories) under their own subdirectory, so
        // each file is its own slot. Without this they escaped eviction entirely and grew the
        // cache without bound.
        let thumbnailRoot = root.appendingPathComponent(Self.thumbnailCacheSubdirectory, isDirectory: true)
        let thumbnailFiles = (try? fileManager.contentsOfDirectory(
            at: thumbnailRoot, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: []
        )) ?? []
        for file in thumbnailFiles {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            slots.append(Slot(url: file, modified: values?.contentModificationDate ?? .distantPast, size: size))
            total += size
        }

        guard total > Self.previewCacheMaxBytes else { return }
        for slot in slots.sorted(by: { $0.modified < $1.modified }) {
            guard total > Self.previewCacheMaxBytes else { break }
            try? fileManager.removeItem(at: slot.url)
            total -= slot.size
        }
    }

    /// One subdirectory per item path, keyed by a SHA256 of the full `item.id`. A hash is
    /// injective in a way slash flattening was not (`a/b` and `a_b` both flattened to `a_b`
    /// and could serve each other's bytes on a matching size/mtime) and can never traverse.
    private static func previewCacheDirectory(for item: FileItem, namespace: String) -> URL {
        let cachesDirectory = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        // The active account is folded into the slot key so two accounts never serve each other's
        // downloaded preview/raw bytes for a matching item id.
        let digest = SHA256.hash(data: Data("\(CacheAccountScope.current)\n\(item.id)".utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return cachesDirectory.appendingPathComponent(Self.previewCacheRootDirectory, isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }

    private static func cacheMetaValue(for item: FileItem) -> String {
        "\(item.dateModified.timeIntervalSince1970)|\(item.size)"
    }

    /// `POST /api/upload`, confirmed against `backend/src/routes/upload.js` +
    /// `services/uploadService.js`. One `multipart/form-data` request per file: the text
    /// fields (`uploadTo`, `relativePath`) MUST precede the `filedata` part — multer's custom
    /// storage reads `req.body` inside `_handleFile`, so a file part that arrives first sees an
    /// empty body. The whole request is first written to a temporary multipart envelope on
    /// disk (one extra copy of the payload), then streamed from that file, so the upload never
    /// sits in memory even for large files. Response is a one-element array of the stored file
    /// (auto-renamed on collision).
    func uploadFile(
        serverURL: URL,
        fileURL: URL,
        fileName: String,
        destination: String,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> FileItem {
        let boundary = "Boundary-\(UUID().uuidString)"
        let envelopeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: envelopeURL) }

        do {
            try Self.writeMultipartEnvelope(
                to: envelopeURL, boundary: boundary, fileURL: fileURL,
                fileName: fileName, destination: destination
            )
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }

        var request = Self.makeRequest(url: serverURL.appendingPathComponent(APIPath.upload), method: .post)
        request.setValue(MIMEType.multipartFormData(boundary: boundary), forHTTPHeaderField: HTTPHeaderField.contentType)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await networkClient.upload(request, envelopeURL, onProgress)
        } catch {
            throw Self.mapTransportError(error)
        }
        try Self.validateReportingMessage(data, response)

        let uploaded: [FileItem]
        do {
            uploaded = try Self.makeDecoder().decode([FileItem].self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        guard let file = uploaded.first else {
            throw FilesClientError.decoding("Upload response was empty.")
        }
        return file
    }

    private static func writeMultipartEnvelope(
        to url: URL, boundary: String, fileURL: URL, fileName: String, destination: String
    ) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        func writeField(_ name: String, _ value: String) throws {
            let part = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
            try handle.write(contentsOf: Data(part.utf8))
        }

        try writeField(MultipartField.uploadDestination, destination)
        try writeField(MultipartField.relativePath, fileName)

        // The server takes the stored name from the `relativePath` field, not this header, but
        // a raw `"` or CR/LF here would still break the multipart framing.
        let headerFileName = fileName
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(MultipartField.fileData)\"; filename=\"\(headerFileName)\"\r\nContent-Type: \(MIMEType.octetStream)\r\n\r\n"
        try handle.write(contentsOf: Data(header.utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }

        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
}
