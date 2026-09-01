import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    static let maxLogoBytes = 2 * 1024 * 1024

    func fetchPreferences(serverURL: URL) async throws -> UserPreferences {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        let request = Self.makeRequest(url: url, method: .get)
        let envelope = try await send(request, decoding: SettingsEnvelope.self)
        return envelope.user ?? UserPreferences()
    }

    func updatePreference(serverURL: URL, key: UserPreferenceKey, value: Bool) async throws {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        request.httpBody = try Self.encode(PatchPreferencesBody(user: [key.rawValue: value]))
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// `GET /api/settings` — extracts the admin-only `thumbnails` + `access.rules`. A
    /// non-admin session just gets no such keys, decoded as nil / empty.
    func fetchSystemSettings(serverURL: URL) async throws -> SystemSettings {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: SystemSettings.self)
    }

    /// `PATCH /api/settings` with a full `{ thumbnails: {...} }` object; the server clamps
    /// each field and echoes `getSettingsForUser`, out of which `thumbnails` is read.
    func updateThumbnailSettings(serverURL: URL, settings: ThumbnailSettings) async throws -> ThumbnailSettings {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            let body = PatchThumbnailsBody(thumbnails: .init(
                enabled: settings.isEnabled,
                size: settings.size,
                quality: settings.quality,
                concurrency: settings.concurrency
            ))
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let echoed = try await sendReportingMessage(request, decoding: SystemSettings.self)
        guard let thumbnails = echoed.thumbnails else {
            throw FilesClientError.decoding("Settings response carried no thumbnails.")
        }
        return thumbnails
    }

    /// `PATCH /api/settings` with `{ access: { rules: [...] } }`; the whole array replaces the
    /// stored rules. The echo's `access.rules` is the server-normalised result.
    func updateAccessRules(serverURL: URL, rules: [AccessRule]) async throws -> [AccessRule] {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            let body = PatchAccessBody(access: .init(rules: rules))
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let echoed = try await sendReportingMessage(request, decoding: SystemSettings.self)
        return echoed.accessRules
    }

    /// `GET /api/branding` (`backend/src/routes/settings.js`) — unauthenticated, returns the
    /// branding object directly (not enveloped).
    func fetchBranding(serverURL: URL) async throws -> Branding {
        let url = serverURL.appendingPathComponent(APIPath.branding)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: Branding.self)
    }

    /// `PATCH /api/settings` with `{ branding: { appName, appLogoUrl } }`. The server merges
    /// and echoes back `getSettingsForUser`, out of which the `branding` object is read.
    func updateBranding(serverURL: URL, appName: String, appLogoUrl: String) async throws -> Branding {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            let body = PatchBrandingBody(branding: .init(appName: appName, appLogoUrl: appLogoUrl))
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await sendReportingMessage(request, decoding: SettingsEnvelope.self)
        guard let branding = envelope.branding else {
            throw FilesClientError.decoding("Settings response carried no branding.")
        }
        return branding
    }

    /// `POST /api/settings/upload-logo` — a single `logo` multipart part. The whole payload is
    /// small (≤2 MB, enforced client and server side), so the envelope is built in memory
    /// rather than streamed from disk like `uploadFile`.
    func uploadServerLogo(serverURL: URL, jpegData: Data) async throws -> String {
        guard jpegData.count <= Self.maxLogoBytes else {
            throw FilesClientError.decoding("Logo image exceeds the \(Self.maxLogoBytes / (1024 * 1024)) MB limit.")
        }
        let url = serverURL.appendingPathComponent(APIPath.uploadLogo)
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = Self.makeRequest(url: url, method: .post)
        request.setValue(MIMEType.multipartFormData(boundary: boundary), forHTTPHeaderField: HTTPHeaderField.contentType)

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(MultipartField.logo)\"; filename=\"logo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: \(MIMEType.jpeg)\r\n\r\n".utf8))
        body.append(jpegData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let envelope = try await sendReportingMessage(request, decoding: LogoUploadEnvelope.self)
        return envelope.logoUrl
    }
}
