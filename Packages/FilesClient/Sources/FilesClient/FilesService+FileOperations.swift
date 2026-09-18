import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    /// `POST /api/files/rename`, confirmed against `backend/src/routes/files/rename.js`:
    /// `path` is the item's *parent* directory, `name` its current name — matching `FileItem`'s
    /// own `path`/`name` fields exactly, so the whole item can be forwarded unchanged.
    func renameItem(serverURL: URL, item: FileItem, newName: String) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.filesRename)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(RenameItemBody(path: item.path, name: item.name, newName: newName))
        let envelope = try await sendReportingMessage(request, decoding: RenameItemEnvelope.self)
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

    /// `POST /api/editor` / `PUT /api/editor`, confirmed against `backend/src/routes/editor.js`:
    /// the real text view/edit path for anything `GET /api/preview` won't serve (415s on
    /// everything outside images/RAW/video/audio/pdf) — plain text, markdown, code, config
    /// files. The server itself enforces a size cap (1MB default) and sniffs for binary
    /// content, surfacing either as a plain validation error this maps to `.server(statusCode:)`.
    func fetchTextContent(serverURL: URL, path: String) async throws -> String {
        do {
            return try await fetchTextContentFromServer(serverURL: serverURL, path: path)
        } catch let error as FilesClientError where error == .offline {
            // Offline: read the pinned copy if this file was downloaded for offline use, otherwise
            // surface the offline error so the editor shows its offline state.
            if let offlineURL = OfflineCache.localURL(forPath: path),
               let bytes = try? Data(contentsOf: offlineURL),
               let text = Self.decodeText(bytes)
            {
                return text
            }
            throw error
        }
    }

    /// Decodes a pinned text file's bytes, trying UTF-8 first, then a couple of common fallbacks so a
    /// non UTF-8 file (Latin-1, UTF-16) still opens offline rather than failing.
    private static func decodeText(_ data: Data) -> String? {
        for encoding: String.Encoding in [.utf8, .isoLatin1, .utf16, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }

    private func fetchTextContentFromServer(serverURL: URL, path: String) async throws -> String {
        let url = serverURL.appendingPathComponent(APIPath.editor)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(EditorPathBody(path: path))
        let envelope = try await sendReportingMessage(request, decoding: EditorContentEnvelope.self)
        return envelope.content
    }

    func saveTextContent(serverURL: URL, path: String, content: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.editor)
        var request = Self.makeRequest(url: url, method: .put)
        request.setJSONContentType()
        request.httpBody = try Self.encode(EditorSaveBody(path: path, content: content))
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    /// `POST /api/files/zip/extract`, confirmed against `backend/src/routes/zip.js`: unpacks
    /// the archive into a *new* sibling folder (named after the zip, deduped if taken) and
    /// returns that folder as an item — there's no listing-only/peek-inside endpoint, and only
    /// `.zip` is supported server-side (`.rar`/`.7z`/etc. 415 with "Only .zip archives...").
    func extractZip(serverURL: URL, item: FileItem) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.zipExtract)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ExtractZipBody(path: item.id))
        let envelope = try await sendReportingMessage(request, decoding: ExtractZipEnvelope.self)
        return envelope.item
    }

    /// `POST /api/files/zip/compress`, confirmed against `backend/src/routes/zip.js`: zips a
    /// single item (file or directory) into a new sibling archive in its own parent folder,
    /// auto-naming it from the source (`defaultZipNameForItems`) when `name` is omitted.
    func compressItem(serverURL: URL, item: FileItem) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.zipCompress)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            let body = CompressItemBody(items: [CompressItemBody.Item(name: item.name, path: item.path)], destination: item.path)
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await sendReportingMessage(request, decoding: CompressItemEnvelope.self)
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
            let body = DeleteItemsBody(items: items.map { DeleteItemsBody.Item(path: $0.path, name: $0.name, kind: $0.kind) })
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await send(request, decoding: DeleteImpact.self)
    }

    /// `DELETE /api/files`, confirmed against `backend/src/routes/files/delete.js` and
    /// `fileTransferService.resolveDeleteTargets`: each item is `{path, name}` — again exactly
    /// `FileItem`'s own fields, `kind` included as the server's fallback for already-missing items.
    func deleteItems(serverURL: URL, items: [FileItem]) async throws {
        let url = serverURL.appendingPathComponent(APIPath.files)
        var request = Self.makeRequest(url: url, method: .delete)
        request.setJSONContentType()
        do {
            let body = DeleteItemsBody(items: items.map { DeleteItemsBody.Item(path: $0.path, name: $0.name, kind: $0.kind) })
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// `POST /api/files/copy` and `POST /api/files/move`, confirmed against
    /// `backend/src/routes/files/transfer.js` and `services/fileTransferService.js`:
    /// `{ items: [{ path, name }], destination }` — `path`/`name` are `FileItem`'s own fields,
    /// same as rename/delete. Name collisions in the destination are resolved server side
    /// (`findAvailableName`). A validation failure (empty destination, source missing, a
    /// folder moved into itself) comes back with a message worth surfacing verbatim.
    func transferItems(
        serverURL: URL, items: [FileItem], destination: String, operation: TransferOperation
    ) async throws -> TransferResult {
        let endpoint = operation == .copy ? "api/files/copy" : "api/files/move"
        let url = serverURL.appendingPathComponent(endpoint)
        var request = Self.makeRequest(url: url, method: .post)
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
        return try await sendReportingMessage(request, decoding: TransferResult.self)
    }
}
