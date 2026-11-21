import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    private enum TusConstants {
        static let maxRetries = 3
        static let maxRestarts = 1
        static let copyBlockBytes = 1_048_576
        static let tusFilePrefix = "\(SessionScratchLocation.uploadEnvelopePrefix)tus-"
        static let maxPlainMessageBytes = 300
    }

    private enum TusFailure: Error {
        /// The server no longer has the upload (expired or never kept): start it again.
        case gone
        /// Worth another attempt from the offset the server reports.
        case retryable(FilesClientError)
    }

    func uploadChunked(
        serverURL: URL,
        fileURL: URL,
        fileName: String,
        destination: String,
        chunkSizeBytes: Int,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        var restarts = 0
        while true {
            do {
                try await runTusUpload(
                    serverURL: serverURL, fileURL: fileURL, fileName: fileName,
                    destination: destination, chunkSizeBytes: chunkSizeBytes, onProgress: onProgress
                )
                return
            } catch TusFailure.gone {
                restarts += 1
                guard restarts <= TusConstants.maxRestarts else {
                    throw FilesClientError.server(statusCode: HTTPStatus.notFound.rawValue)
                }
            }
        }
    }

    private func runTusUpload(
        serverURL: URL,
        fileURL: URL,
        fileName: String,
        destination: String,
        chunkSizeBytes: Int,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let size = try Self.fileSize(of: fileURL)
        let uploadURL = try await createTusUpload(
            serverURL: serverURL, size: size, fileName: fileName, destination: destination
        )
        do {
            var offset = 0
            var failures = 0
            while offset < size {
                let length = min(chunkSizeBytes, size - offset)
                do {
                    offset = try await sendTusChunk(
                        uploadURL: uploadURL, fileURL: fileURL, offset: offset, length: length,
                        totalSize: size, onProgress: onProgress
                    )
                    failures = 0
                } catch let TusFailure.retryable(error) {
                    failures += 1
                    guard failures <= TusConstants.maxRetries else { throw error }
                    offset = try await tusOffset(uploadURL: uploadURL)
                }
            }
            onProgress(1)
        } catch {
            if Task.isCancelled || error is CancellationError {
                let request = TusUpload.deleteRequest(uploadURL: uploadURL)
                let service = self
                Task.detached { _ = try? await service.performSend(request) }
            }
            throw error
        }
    }

    private func createTusUpload(
        serverURL: URL,
        size: Int,
        fileName: String,
        destination: String
    ) async throws -> URL {
        let request = TusUpload.createRequest(
            serverURL: serverURL, length: size, fileName: fileName, destination: destination
        )
        let (data, response) = try await performSend(request)
        guard response.statusCode == HTTPStatus.created else { throw Self.tusFailure(data, response) }
        let location = response.value(forHTTPHeaderField: TusUpload.Header.location)
        guard let url = TusUpload.uploadURL(serverURL: serverURL, location: location) else {
            throw FilesClientError.decoding(TusUpload.Header.location)
        }
        return url
    }

    /// Uploads `length` bytes starting at `offset` and returns the offset the server now holds.
    private func sendTusChunk(
        uploadURL: URL,
        fileURL: URL,
        offset: Int,
        length: Int,
        totalSize: Int,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> Int {
        let chunkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(TusConstants.tusFilePrefix)\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: chunkURL) }
        do {
            try Self.copyBytes(from: fileURL, offset: offset, length: length, to: chunkURL)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await networkClient.upload(
                TusUpload.patchRequest(uploadURL: uploadURL, offset: offset),
                chunkURL
            ) { fraction in
                onProgress((Double(offset) + fraction * Double(length)) / Double(totalSize))
            }
        } catch {
            let mapped = Self.mapTransportError(error)
            if case .network = mapped, !Task.isCancelled {
                throw TusFailure.retryable(mapped)
            }
            if case .timedOut = mapped {
                throw TusFailure.retryable(mapped)
            }
            throw mapped
        }

        switch response.statusCode {
        case HTTPStatus.noContent, HTTPStatus.ok:
            guard let next = TusUpload.offset(of: response), next > offset else {
                throw FilesClientError.decoding(TusUpload.Header.uploadOffset)
            }
            return next
        case HTTPStatus.notFound, HTTPStatus.gone:
            throw TusFailure.gone
        case HTTPStatus.conflict:
            throw TusFailure.retryable(Self.tusFailure(data, response))
        default:
            let failure = Self.tusFailure(data, response)
            // A finalize refusal says a retry cannot help; any other 5xx may be a proxy hiccup.
            let isFinalizeRefusal = TusUpload.finalizeError(of: response) != nil
            if HTTPStatus.serverError ~= response.statusCode,
               response.statusCode != HTTPStatus.insufficientStorage, !isFinalizeRefusal
            {
                throw TusFailure.retryable(failure)
            }
            throw failure
        }
    }

    private func tusOffset(uploadURL: URL) async throws -> Int {
        let (data, response) = try await performSend(TusUpload.headRequest(uploadURL: uploadURL))
        switch response.statusCode {
        case HTTPStatus.ok:
            guard let offset = TusUpload.offset(of: response) else {
                throw FilesClientError.decoding(TusUpload.Header.uploadOffset)
            }
            return offset
        case HTTPStatus.notFound, HTTPStatus.gone:
            throw TusFailure.gone
        default:
            throw Self.tusFailure(data, response)
        }
    }

    /// A refusal in the server's own words: the finalize header, else a short plain text body
    /// (tus answers in text, not the JSON the rest of the API uses).
    private static func tusFailure(_ data: Data, _ response: HTTPURLResponse) -> FilesClientError {
        if let message = TusUpload.finalizeError(of: response) {
            return .serverMessage(statusCode: response.statusCode, message: message)
        }
        do {
            try validateReportingMessage(data, response)
        } catch let error as FilesClientError {
            if case .server = error, let text = plainMessage(data) {
                return .serverMessage(statusCode: response.statusCode, message: text)
            }
            return error
        } catch {
            return .server(statusCode: response.statusCode)
        }
        return .server(statusCode: response.statusCode)
    }

    private static func plainMessage(_ data: Data) -> String? {
        guard data.count <= TusConstants.maxPlainMessageBytes,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("{"), !text.hasPrefix("<")
        else { return nil }
        return text
    }

    static func fileSize(of url: URL) throws -> Int {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.intValue ?? 0
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// Copies a byte range in small blocks so a large chunk never sits in memory whole.
    private static func copyBytes(from source: URL, offset: Int, length: Int, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try input.seek(toOffset: UInt64(offset))
        var remaining = length
        while remaining > 0 {
            let more = try autoreleasepool {
                guard let block = try input.read(upToCount: min(TusConstants.copyBlockBytes, remaining)),
                      !block.isEmpty
                else { return false }
                try output.write(contentsOf: block)
                remaining -= block.count
                return true
            }
            if !more {
                break
            }
        }
    }
}
