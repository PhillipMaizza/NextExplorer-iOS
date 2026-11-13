import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    /// `POST /api/files/rename`, confirmed against `backend/src/routes/files/rename.js`:
    /// `path` is the item's *parent* directory, `name` its current name: matching `FileItem`'s
    /// own `path`/`name` fields exactly, so the whole item can be forwarded unchanged.
    func renameItem(serverURL: URL, item: FileItem, newName: String) async throws -> FileItem {
        let scope = activeScope()
        let url = serverURL.appendingPathComponent(APIPath.filesRename)
        var request = Self.makeRequest(url: url, method: .post, isMutation: true)
        request.setJSONContentType()
        request.httpBody = try Self.encode(RenameItemBody(path: item.path, name: item.name, newName: newName))
        let envelope = try await sendReportingMessage(request, decoding: RenameItemEnvelope.self)
        textEditorETags.forget(scope: scope, serverURL: serverURL, path: item.id)
        return envelope.item
    }

    /// `POST /api/files/folder`, confirmed against `backend/src/routes/files/folder.js`: `path`
    /// is the parent directory's relative path (the server 400s an empty one), `name` the new
    /// folder's name. Responds 201 `{ item }` with the created folder, its name possibly
    /// suffixed on a collision.
    func createFolder(serverURL: URL, path: String, name: String) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.filesFolder)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(CreateFolderBody(path: path, name: name))
        let envelope = try await sendReportingMessage(request, decoding: CreateFolderEnvelope.self)
        return envelope.item
    }

    func createFile(serverURL: URL, path: String, name: String) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.filesFile)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(CreateFolderBody(path: path, name: name))
        let envelope = try await sendReportingMessage(request, decoding: CreateFolderEnvelope.self)
        return envelope.item
    }

    /// `POST /api/editor` / `PUT /api/editor`, confirmed against `backend/src/routes/editor.js`:
    /// the real text view/edit path for anything `GET /api/preview` won't serve (415s on
    /// everything outside images/RAW/video/audio/pdf): plain text, markdown, code, config
    /// files. The server itself enforces a size cap (1MB default) and sniffs for binary
    /// content, surfacing either as a plain validation error this maps to `.server(statusCode:)`.
    func fetchTextContent(serverURL: URL, path: String) async throws -> String {
        let scope = activeScope()
        do {
            return try await fetchTextContentFromServer(serverURL: serverURL, path: path)
        } catch let error as FilesClientError where error == .offline {
            if let offlineURL = OfflineCache.localURL(forPath: path, scope: scope),
               let text = Self.offlineEditorText(at: offlineURL)
            {
                return text
            }
            throw error
        }
    }

    /// The pinned copy as editor text, refused above the backend editor cap (so the offline editor
    /// never opens what the server would not) and when the bytes are not plain text.
    static func offlineEditorText(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size <= EditorLimits.maxFileSizeBytes,
              let bytes = try? Data(contentsOf: url)
        else { return nil }
        return decodeText(bytes)
    }

    enum EditorLimits {
        /// `MAX_EDITOR_FILE_SIZE` in `backend/src/services/textEditorService.js` (its default, which
        /// `config.editor.maxFileSizeBytes` can raise).
        static let maxFileSizeBytes = 1 * bytesPerKibibyte * bytesPerKibibyte
        static let bytesPerKibibyte = 1024
    }

    /// Decodes a pinned text file's bytes, or nil when they are not plain text (a NUL or another
    /// control character in the decoded result is the tell of binary data).
    static func decodeText(_ data: Data) -> String? {
        guard let text = decodeCandidate(data), !text.unicodeScalars.contains(where: TextDecoding.isBinaryTell) else {
            return nil
        }
        return text
    }

    /// A byte order mark decides first, then markless UTF 16 (only when its zero byte pattern gives it
    /// away, since any even length data decodes as UTF 16, and it must precede UTF 8 because zero bytes
    /// are valid UTF 8), then strict UTF 8, then Windows 1252, and Latin 1 last because it accepts
    /// every byte.
    private static func decodeCandidate(_ data: Data) -> String? {
        for mark in ByteOrderMark.all where data.starts(with: mark.bytes) {
            let body = data.dropFirst(mark.bytes.count)
            if let text = String(data: body, encoding: mark.encoding) {
                return text
            }
            // A mark in front of bytes that do not decode as that encoding was a coincidence of a
            // legacy encoded file, so the legacy decoding gets the bytes instead of nil.
            return legacyDecode(mark.encoding == .utf8 ? Data(body) : data)
        }
        if let encoding = marklessUTF16Encoding(of: data), let text = String(data: data, encoding: encoding) {
            return text
        }
        let utf8Text = String(data: data, encoding: .utf8)
        // Cyrillic, Greek or Hebrew UTF 16 is also valid UTF 8, made of control characters, so UTF 8
        // only wins when it reads like text.
        if let utf8Text, !utf8Text.unicodeScalars.contains(where: TextDecoding.isUnexpectedControl) {
            return utf8Text
        }
        if let text = nonLatinUTF16Text(of: data) {
            return text
        }
        return utf8Text ?? legacyDecode(data)
    }

    private static func legacyDecode(_ data: Data) -> String? {
        String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Markless UTF 16 of CJK, Cyrillic or other non Latin text has no zero bytes to give it away.
    /// Accepted only when one byte order decodes cleanly, almost every code unit is a character of a
    /// known script (or plain ASCII), and the text is not the byte pair pattern of ASCII shaped
    /// legacy text read two bytes at a time, which also lands in the CJK block.
    private static func nonLatinUTF16Text(of data: Data) -> String? {
        guard data.count >= TextDecoding.minimumUTF16Bytes,
              data.count.isMultiple(of: TextDecoding.utf16UnitBytes)
        else {
            return nil
        }
        let candidates = [String.Encoding.utf16LittleEndian, .utf16BigEndian].compactMap { encoding -> String? in
            guard let text = String(data: data, encoding: encoding), isPlausibleUTF16Text(text),
                  !isASCIIPairPattern(data, encoding: encoding)
            else { return nil }
            return text
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func isPlausibleUTF16Text(_ text: String) -> Bool {
        var plausibleCount = 0
        var totalCount = 0
        for scalar in text.unicodeScalars {
            totalCount += 1
            if scalar == TextDecoding.replacementScalar {
                return false
            }
            if TextDecoding.plausibleScalarRanges.contains(where: { $0.contains(scalar.value) }) {
                plausibleCount += 1
            }
        }
        guard totalCount > 0 else { return false }
        return Double(plausibleCount) / Double(totalCount) >= TextDecoding.minimumPlausibleShare
    }

    private static func isASCIIPairPattern(_ data: Data, encoding _: String.Encoding) -> Bool {
        let bytes = Array(data.prefix(TextDecoding.sampleBytes))
        let pairs = stride(from: 0, to: bytes.count - 1, by: TextDecoding.utf16UnitBytes).map { (
            bytes[$0],
            bytes[$0 + 1]
        ) }
        guard !pairs.isEmpty else { return false }
        let asciiPairs = pairs.filter {
            TextDecoding.printableASCIIBytes.contains($0.0) && TextDecoding.printableASCIIBytes.contains($0.1)
        }
        return Double(asciiPairs.count) / Double(pairs.count) > TextDecoding.maximumASCIIPairShare
    }

    private struct ByteOrderMark {
        let bytes: [UInt8]
        let encoding: String.Encoding

        /// UTF 32 little endian first: its mark begins with the whole UTF 16 little endian mark.
        static let all = [
            ByteOrderMark(bytes: [0xFF, 0xFE, 0x00, 0x00], encoding: .utf32LittleEndian),
            ByteOrderMark(bytes: [0x00, 0x00, 0xFE, 0xFF], encoding: .utf32BigEndian),
            ByteOrderMark(bytes: [0xEF, 0xBB, 0xBF], encoding: .utf8),
            ByteOrderMark(bytes: [0xFF, 0xFE], encoding: .utf16LittleEndian),
            ByteOrderMark(bytes: [0xFE, 0xFF], encoding: .utf16BigEndian),
        ]
    }

    /// Text in UTF 16 without a mark has a zero byte beside most characters, always at the same
    /// parity. Real Latin 1 or Windows 1252 text has no zero bytes at all.
    private static func marklessUTF16Encoding(of data: Data) -> String.Encoding? {
        let evenCount = min(data.count, TextDecoding.sampleBytes) / 2 * 2
        guard evenCount >= 2 else { return nil }
        let sample = Array(data.prefix(evenCount))
        var zerosAtEven = 0
        var zerosAtOdd = 0
        for (index, byte) in sample.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) {
                zerosAtEven += 1
            } else {
                zerosAtOdd += 1
            }
        }
        let threshold = sample.count / TextDecoding.minimumZeroShareDivisor
        if zerosAtOdd >= threshold, zerosAtEven == 0, zerosAtOdd > 0 {
            return .utf16LittleEndian
        }
        if zerosAtEven >= threshold, zerosAtOdd == 0, zerosAtEven > 0 {
            return .utf16BigEndian
        }
        return nil
    }

    private enum TextDecoding {
        static let sampleBytes = 512
        /// A zero byte beside at least a quarter of the sampled bytes marks UTF 16 text.
        static let minimumZeroShareDivisor = 4
        static let utf16UnitBytes = 2
        /// Sixteen code units: shorter data is too little evidence to call it UTF 16, since random bytes
        /// pass the per unit checks often enough at four.
        static let minimumUTF16Bytes = 32
        static let minimumPlausibleShare = 0.95
        /// Half of real CJK units have both bytes in the printable ASCII range; ASCII shaped legacy
        /// text read as UTF 16 has nearly all of them there.
        static let maximumASCIIPairShare = 0.6
        static let printableASCIIBytes: ClosedRange<UInt8> = 0x20 ... 0x7E

        static let replacementScalar = Unicode.Scalar(0xFFFD) ?? " "
        static let firstPrintableScalar: UInt32 = 0x20
        static let textControlScalars: Set<Unicode.Scalar> = ["\t", "\n", "\r"]

        static func isUnexpectedControl(_ scalar: Unicode.Scalar) -> Bool {
            scalar.value < firstPrintableScalar && !textControlScalars.contains(scalar)
        }

        /// C0 controls other than tab, line feed and carriage return, plus DEL and the C1 controls
        /// (which is what Latin 1 turns the bytes Windows 1252 leaves undefined into).
        static let deleteScalar: UInt32 = 0x7F
        static let lastC1ControlScalar: UInt32 = 0x9F

        static func isBinaryTell(_ scalar: Unicode.Scalar) -> Bool {
            isUnexpectedControl(scalar) || (deleteScalar ... lastC1ControlScalar).contains(scalar.value)
        }

        static let plausibleScalarRanges: [ClosedRange<UInt32>] = [
            0x09 ... 0x0A, 0x0D ... 0x0D, 0x20 ... 0x7E,
            0x0370 ... 0x03FF, 0x0400 ... 0x04FF, 0x0590 ... 0x05FF, 0x0600 ... 0x06FF,
            0x0900 ... 0x097F, 0x0E00 ... 0x0E7F, 0x3000 ... 0x30FF, 0x3400 ... 0x4DBF,
            0x4E00 ... 0x9FFF, 0xAC00 ... 0xD7AF, 0xFF00 ... 0xFFEF, 0x20000 ... 0x2FFFF,
        ]
    }

    private enum EditorQuery {
        static let pathName = "path"
        /// Everything outside the unreserved characters and the path separator is percent encoded, so
        /// `+`, `&`, `#`, `%` and spaces survive: `URLQueryItem` leaves `+` and `&` as they are.
        static let allowedPathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
    }

    private enum EditorPreflight {
        static let notModifiedStatus = 304
        static let clientErrorStatuses = 400 ..< 500
        static let successStatuses = 200 ..< 300
        /// Answers the shared validation turns into their own errors instead of a conflict prompt.
        static let reportedStatuses: Set<Int> = [401, 403, 429]
    }

    private func fetchTextContentFromServer(serverURL: URL, path: String) async throws -> String {
        let key = Self.editorKey(activeScope(), serverURL, path)
        let url = serverURL.appendingPathComponent(APIPath.editor)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(EditorPathBody(path: path))
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
        let envelope: EditorContentEnvelope
        do {
            envelope = try Self.makeDecoder().decode(EditorContentEnvelope.self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        textEditorETags.set(response.value(forHTTPHeaderField: HTTPHeaderField.etag), for: key)
        return envelope.content
    }

    /// `PUT /api/editor` has no `If Match` precondition (`backend/src/routes/editor.js` writes
    /// whatever it is given, keeping the replaced state as a version). The read, by POST or GET, carries
    /// the same ETag (`textFileEtag` through `sendTextFile`) and a GET or HEAD answers 304 to
    /// `If None Match`, so just before the write a HEAD revalidates the file against the ETag the editor
    /// opened it with, without downloading the body. A change, a missing file or an answer that cannot
    /// confirm the file is unchanged throws `.changedOnServer` once and forgets the ETag, so the next
    /// save of the same text is the user's deliberate overwrite. A successful save stores the ETag the
    /// PUT answers with (only present when the file at the path is the one just written), which
    /// protects the following save; without one the next save is unprotected.
    func saveTextContent(serverURL: URL, path: String, content: String) async throws {
        let key = Self.editorKey(activeScope(), serverURL, path)
        if let knownETag = textEditorETags.etag(for: key),
           try await hasChangedOnServer(serverURL: serverURL, path: path, knownETag: knownETag)
        {
            textEditorETags.set(nil, for: key)
            throw FilesClientError.changedOnServer
        }
        let url = serverURL.appendingPathComponent(APIPath.editor)
        var request = Self.makeRequest(url: url, method: .put, isMutation: true)
        request.setJSONContentType()
        request.httpBody = try Self.encode(EditorSaveBody(path: path, content: content))
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
        textEditorETags.set(response.value(forHTTPHeaderField: HTTPHeaderField.etag), for: key)
    }

    /// Whether the file may no longer be the one the editor opened. The conditional HEAD answers 304
    /// for an unchanged file; 200 means it differs, 404 that it was deleted or renamed, and any other
    /// 4xx (the backend runs `readTextFile` on a HEAD, so a file that grew past the editor cap or turned
    /// binary answers 4xx) cannot confirm anything, so none of them may be overwritten blindly. Auth,
    /// rate limit and server errors surface as themselves.
    private func hasChangedOnServer(serverURL: URL, path: String, knownETag: String) async throws -> Bool {
        guard var components = URLComponents(
            url: serverURL.appendingPathComponent(APIPath.editor), resolvingAgainstBaseURL: false
        ), let encodedPath = path.addingPercentEncoding(withAllowedCharacters: EditorQuery.allowedPathCharacters)
        else { return false }
        components.percentEncodedQueryItems = [URLQueryItem(name: EditorQuery.pathName, value: encodedPath)]
        guard let url = components.url else { return false }
        var request = Self.makeRequest(url: url, method: .head)
        request.setValue(knownETag, forHTTPHeaderField: HTTPHeaderField.ifNoneMatch)
        let (_, response) = try await performSend(request)
        let status = response.statusCode
        if status == EditorPreflight.notModifiedStatus {
            return false
        }
        if EditorPreflight.successStatuses.contains(status) {
            return true
        }
        if EditorPreflight.clientErrorStatuses.contains(status), !EditorPreflight.reportedStatuses.contains(status) {
            return true
        }
        try Self.validate(response)
        return true
    }

    private static func editorKey(_ scope: String, _ serverURL: URL, _ path: String) -> String {
        TextEditorETagStore.key(scope: scope, serverURL: serverURL, path: path)
    }

    /// `POST /api/files/zip/extract`, confirmed against `backend/src/routes/zip.js`: unpacks
    /// the archive into a *new* sibling folder (named after the zip, deduped if taken) and
    /// returns that folder as an item: there's no listing only or peek inside endpoint, and only
    /// `.zip` is supported server side (`.rar`/`.7z`/etc. 415 with "Only .zip archives...").
    func extractZip(serverURL: URL, item: FileItem) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.zipExtract)
        var request = Self.makeRequest(url: url, method: .post, isMutation: true)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ExtractZipBody(path: item.id))
        let envelope = try await sendArchiveOperation(request, decoding: ExtractZipEnvelope.self)
        return envelope.item
    }

    /// `POST /api/files/zip/compress`, confirmed against `backend/src/routes/zip.js`: zips a
    /// single item (file or directory) into a new sibling archive in its own parent folder,
    /// auto naming it from the source (`defaultZipNameForItems`) when `name` is omitted.
    func compressItem(serverURL: URL, item: FileItem) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.zipCompress)
        var request = Self.makeRequest(url: url, method: .post, isMutation: true)
        request.setJSONContentType()
        do {
            let body = CompressItemBody(
                items: [CompressItemBody.Item(name: item.name, path: item.path)],
                destination: item.path
            )
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await sendArchiveOperation(request, decoding: CompressItemEnvelope.self)
        return envelope.item
    }

    /// `POST /api/files/delete-impact`, confirmed against `backend/src/routes/files/delete.js`
    /// and `fileTransferService.getDeleteImpact`: same `{path, name, kind}` item shape as the
    /// delete itself, answering with the count of share links that deleting those items would
    /// break. Used to warn before the fact; the delete still enforces regardless.
    func deleteImpact(serverURL: URL, items: [FileItem]) async throws -> DeleteImpact {
        let url = serverURL.appendingPathComponent(APIPath.filesDeleteImpact)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            let body = DeleteItemsBody(items: items.map { DeleteItemsBody.Item(
                path: $0.path,
                name: $0.name,
                kind: $0.kind
            ) })
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await send(request, decoding: DeleteImpact.self)
    }

    /// `DELETE /api/files`, confirmed against `backend/src/routes/files/delete.js` and
    /// `fileTransferService.resolveDeleteTargets`: each item is `{path, name}`; again exactly
    /// `FileItem`'s own fields, `kind` included as the server's fallback for already missing items.
    func deleteItems(serverURL: URL, items: [FileItem]) async throws {
        let scope = activeScope()
        let url = serverURL.appendingPathComponent(APIPath.files)
        var request = Self.makeRequest(url: url, method: .delete, isMutation: true)
        request.setJSONContentType()
        do {
            let body = DeleteItemsBody(items: items.map { DeleteItemsBody.Item(
                path: $0.path,
                name: $0.name,
                kind: $0.kind
            ) })
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
        for item in items {
            textEditorETags.forget(scope: scope, serverURL: serverURL, path: item.id)
        }
    }

    /// `POST /api/files/copy` and `POST /api/files/move`, confirmed against
    /// `backend/src/routes/files/transfer.js` and `services/fileTransferService.js`:
    /// `{ items: [{ path, name }], destination }`; `path`/`name` are `FileItem`'s own fields,
    /// same as rename/delete. Name collisions in the destination are resolved server side
    /// (`findAvailableName`). A validation failure (empty destination, source missing, a
    /// folder moved into itself) comes back with a message worth surfacing verbatim.
    func transferItems(
        serverURL: URL, items: [FileItem], destination: String, operation: TransferOperation
    ) async throws -> TransferResult {
        let scope = activeScope()
        let endpoint = operation == .copy ? APIPath.filesCopy : APIPath.filesMove
        let url = serverURL.appendingPathComponent(endpoint)
        var request = Self.makeRequest(url: url, method: .post, isMutation: true)
        request.setJSONContentType()
        do {
            let body = TransferItemsBody(
                items: items.map { TransferItemsBody.Item(path: $0.path, name: $0.name) },
                destination: destination
            )
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let result = try await sendReportingMessage(request, decoding: TransferResult.self)
        if operation == .move {
            for item in items {
                textEditorETags.forget(scope: scope, serverURL: serverURL, path: item.id)
            }
        }
        return result
    }
}
