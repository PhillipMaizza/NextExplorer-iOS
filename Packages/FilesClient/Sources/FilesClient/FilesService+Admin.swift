import CoreModels
import Foundation
import NetworkClient

extension FilesService {
    /// `POST /api/auth/password`, verified against `backend/src/routes/auth.js` and
    /// `services/users/localAuth.js` `changeLocalPassword`: `{ currentPassword, newPassword }`
    /// returns 204. The route is rate limited (429) and rejects a wrong current password (401
    /// "Current password is incorrect.") or a password below the minimum length (400).
    func changeOwnPassword(serverURL: URL, currentPassword: String, newPassword: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.changeOwnPassword)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ChangeOwnPasswordBody(
            currentPassword: currentPassword, newPassword: newPassword
        ))
        let (data, response) = try await performSend(request)
        // Unlike every other call, a 401 here is "current password is incorrect", not a dead
        // session, so it must reach the user as its message, not as `.sessionExpired`.
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 429:
            throw FilesClientError.rateLimited
        default:
            if let message = Self.errorMessage(from: data) {
                throw FilesClientError.serverMessage(statusCode: response.statusCode, message: message)
            }
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    /// `GET /api/features`. Every flag section is a `{ enabled: Bool }` object; `ServerFeatures`
    /// only pulls the ones this app acts on.
    func serverFeatures(serverURL: URL) async throws -> ServerFeatures {
        let url = serverURL.appendingPathComponent(APIPath.features)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: ServerFeatures.self)
    }

    /// `GET /api/users` (admin), wrapped `{ users: [...] }`, each with `roles` and `authMethods`.
    func listUsers(serverURL: URL) async throws -> [User] {
        let url = serverURL.appendingPathComponent(APIPath.users)
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: UsersEnvelope.self).users
    }

    /// `POST /api/users` (admin) → 201 `{ user }`.
    func createUser(serverURL: URL, request: CreateUserRequest) async throws -> User {
        let url = serverURL.appendingPathComponent(APIPath.users)
        var httpRequest = Self.makeRequest(url: url, method: .post)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(CreateUserBody(
            email: request.email,
            username: request.username,
            password: request.password,
            displayName: request.displayName,
            roles: request.isAdmin ? [UserRole.admin] : []
        ))
        return try await sendReportingMessage(httpRequest, decoding: UserEnvelope.self).user
    }

    /// `PATCH /api/users/:id` (admin) returns `{ user }`. Only the non nil fields of `request`
    /// are sent, matching the server's "update just what's present" behaviour.
    func updateUser(serverURL: URL, userID: String, request: UpdateUserRequest) async throws -> User {
        let url = serverURL.appendingPathComponent(APIPath.users).appendingPathComponent(userID)
        var httpRequest = Self.makeRequest(url: url, method: .patch)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(UpdateUserBody(
            email: request.email,
            username: request.username,
            displayName: request.displayName,
            roles: request.roles
        ))
        return try await sendReportingMessage(httpRequest, decoding: UserEnvelope.self).user
    }

    /// `POST /api/users/:id/password` (admin) → 204.
    func setUserPassword(serverURL: URL, userID: String, newPassword: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.users).appendingPathComponent(userID).appendingPathComponent(APIPath.Component.password)
        var httpRequest = Self.makeRequest(url: url, method: .post)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(NewPasswordBody(newPassword: newPassword))
        let (data, response) = try await performSend(httpRequest)
        try Self.validateReportingMessage(data, response)
    }

    /// `DELETE /api/users/:id` (admin) returns 204. The server rejects deleting yourself or the
    /// last admin, with a message this surfaces verbatim.
    func deleteUser(serverURL: URL, userID: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.users).appendingPathComponent(userID)
        let request = Self.makeRequest(url: url, method: .delete)
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    /// `GET /api/users/:id/volumes` (admin, `USER_VOLUMES` feature).
    func userVolumes(serverURL: URL, userID: String) async throws -> [UserVolume] {
        let url = Self.userVolumesURL(serverURL: serverURL, userID: userID)
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: UserVolumesEnvelope.self).volumes
    }

    /// `POST /api/users/:id/volumes` → 201 `{ volume }`.
    func addUserVolume(serverURL: URL, userID: String, request: AddUserVolumeRequest) async throws -> UserVolume {
        let url = Self.userVolumesURL(serverURL: serverURL, userID: userID)
        var httpRequest = Self.makeRequest(url: url, method: .post)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(AddUserVolumeBody(
            label: request.label,
            path: request.path,
            accessMode: request.accessMode.rawValue
        ))
        return try await sendReportingMessage(httpRequest, decoding: UserVolumeEnvelope.self).volume
    }

    /// `PATCH /api/users/:id/volumes/:volumeID`. The server accepts label and access mode; the
    /// path itself is immutable once assigned.
    func updateUserVolume(
        serverURL: URL, userID: String, volumeID: String, label: String?, accessMode: ShareAccessMode
    ) async throws -> UserVolume {
        let url = Self.userVolumesURL(serverURL: serverURL, userID: userID).appendingPathComponent(volumeID)
        var httpRequest = Self.makeRequest(url: url, method: .patch)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(UpdateUserVolumeBody(label: label, accessMode: accessMode.rawValue))
        return try await sendReportingMessage(httpRequest, decoding: UserVolumeEnvelope.self).volume
    }

    /// `DELETE /api/users/:id/volumes/:volumeID` → 204.
    func removeUserVolume(serverURL: URL, userID: String, volumeID: String) async throws {
        let url = Self.userVolumesURL(serverURL: serverURL, userID: userID).appendingPathComponent(volumeID)
        let request = Self.makeRequest(url: url, method: .delete)
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    /// `GET /api/admin/browse-directories?path=`. Omit `path` to start at the server's
    /// configured volume root.
    func browseAdminDirectories(serverURL: URL, path: String?) async throws -> AdminDirectoryListing {
        var components = URLComponents(
            url: serverURL.appendingPathComponent(APIPath.adminBrowseDirectories),
            resolvingAgainstBaseURL: false
        )
        if let path, !path.isEmpty {
            components?.queryItems = [URLQueryItem(name: QueryKey.path, value: path)]
        }
        guard let url = components?.url else { throw FilesClientError.network("Bad URL") }
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: AdminDirectoryListing.self)
    }

    private static func userVolumesURL(serverURL: URL, userID: String) -> URL {
        serverURL
            .appendingPathComponent(APIPath.users)
            .appendingPathComponent(userID)
            .appendingPathComponent(APIPath.Component.volumes)
    }
}
