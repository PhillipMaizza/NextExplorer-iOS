import CoreModels
@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// The permission and branding routes through `FilesClient.live` against a stubbed `URLSession`. Nested in
/// `FilesClientLiveTests` so it inherits `.serialized`: every live client suite shares `StubURLProtocol`'s statics.
extension FilesClientLiveTests {
    struct FilesClientPermissionsAndBrandingTests: FilesClientLiveHarness {
        private enum Constants {
            static let appName = "Acme Files"
            static let logoPath = "/uploads/logo.png"
            static let logoBytes = "JPEGBYTES"
            static let ownerName = "alice"
            static let groupName = "staff"
            static let maxLogoBytes = 2 * 1024 * 1024
            static let defaultRequestTimeout = URLRequest(url: URL(fileURLWithPath: "/")).timeoutInterval
        }

        // MARK: fetchPermissions

        @Test
        func fetchPermissionsGetsTheWildcardRouteAndDecodesTheMode() async throws {
            try prepare(statusCode: 200, fixture: .permissionsFile644)

            let permissions = try await makeClient().fetchPermissions(serverURL, TestPath.docsNote)

            try expectRequest(.get, "/api/permissions/Docs/n.txt")
            #expect(permissions.path == "Docs/a.txt")
            #expect(permissions.octalString == "644")
            #expect(permissions.owner == Constants.ownerName)
            #expect(permissions.group == Constants.groupName)
            #expect(permissions.uid == 501)
            #expect(permissions.gid == 20)
            #expect(!permissions.isDirectory)
            #expect(permissions.can(.owner, .write))
            #expect(!permissions.can(.others, .write))
        }

        @Test
        func fetchPermissionsEncodesEachSegmentOfAnAwkwardPath() async throws {
            try prepare(statusCode: 200, fixture: .permissionsFile644)

            _ = try await makeClient().fetchPermissions(serverURL, "Docs/My File #1.txt")

            #expect(StubURLProtocol.capturedRequest?.url?.absoluteString == "https://example.com/api/permissions/Docs/My%20File%20%231.txt")
        }

        @Test
        func fetchPermissionsOfTheRootKeepsATrailingSlash() async throws {
            try prepare(statusCode: 200, fixture: .permissionsFile644)

            _ = try await makeClient().fetchPermissions(serverURL, "")

            #expect(StubURLProtocol.capturedRequest?.url?.absoluteString == "https://example.com/api/permissions/")
        }

        @Test
        func fetchPermissionsSurfacesTheDenialReasonOnA403() async throws {
            try prepare(statusCode: 403, fixture: .permissionsErrorDenied)

            await #expect(throws: FilesClientError.forbidden(message: "Access denied by rule.")) {
                _ = try await makeClient().fetchPermissions(serverURL, TestPath.docsNote)
            }
        }

        // MARK: changePermissions

        struct ChmodCase: Sendable {
            let mode: String
            let isRecursive: Bool
        }

        nonisolated static let chmodCases = [
            ChmodCase(mode: "644", isRecursive: false),
            ChmodCase(mode: "755", isRecursive: true),
            ChmodCase(mode: "000", isRecursive: false),
        ]

        @Test(arguments: chmodCases)
        func changePermissionsPostsThePathModeAndRecursionFlag(_ chmod: ChmodCase) async throws {
            prepareEmpty(statusCode: 200)

            try await makeClient().changePermissions(serverURL, TestFolder.docs, chmod.mode, chmod.isRecursive)

            try expectRequest(.post, "/api/permissions/chmod")
            try expectJSONBody(["path": TestFolder.docs, "mode": chmod.mode, "recursive": chmod.isRecursive])
        }

        @Test
        func changePermissionsGetsTheLongMutationBudget() async throws {
            prepareEmpty(statusCode: 200)

            try await makeClient().changePermissions(serverURL, TestFolder.docs, "755", true)

            let timeout = try #require(StubURLProtocol.capturedRequest?.timeoutInterval)
            #expect(timeout > Constants.defaultRequestTimeout)
        }

        @Test
        func changePermissionsSurfacesTheInvalidModeMessage() async throws {
            try prepare(statusCode: 400, fixture: .permissionsErrorInvalidMode)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 400, message: "Mode must be three octal digits.")) {
                try await makeClient().changePermissions(serverURL, TestFolder.docs, "9", false)
            }
        }

        // MARK: changeOwnership

        @Test
        func changeOwnershipSendsOwnerAndGroupWhenBothAreGiven() async throws {
            prepareEmpty(statusCode: 200)

            try await makeClient().changeOwnership(serverURL, TestFolder.docs, Constants.ownerName, Constants.groupName)

            try expectRequest(.post, "/api/permissions/chown")
            try expectJSONBody(["path": TestFolder.docs, "owner": Constants.ownerName, "group": Constants.groupName])
        }

        @Test
        func changeOwnershipOmitsTheGroupKeyWhenItIsNil() async throws {
            prepareEmpty(statusCode: 200)

            try await makeClient().changeOwnership(serverURL, TestFolder.docs, Constants.ownerName, nil)

            try expectJSONBody(["path": TestFolder.docs, "owner": Constants.ownerName])
        }

        @Test
        func changeOwnershipOmitsTheOwnerKeyWhenItIsNil() async throws {
            prepareEmpty(statusCode: 200)

            try await makeClient().changeOwnership(serverURL, TestFolder.docs, nil, Constants.groupName)

            try expectJSONBody(["path": TestFolder.docs, "group": Constants.groupName])
        }

        @Test
        func changeOwnershipWithNeitherSendsOnlyThePathAndLetsTheServerRefuse() async throws {
            try prepare(statusCode: 400, fixture: .permissionsErrorInvalidMode)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 400, message: "Mode must be three octal digits.")) {
                try await makeClient().changeOwnership(serverURL, TestFolder.docs, nil, nil)
            }
            try expectJSONBody(["path": TestFolder.docs])
        }

        // MARK: branding

        @Test
        func fetchBrandingReadsTheUnenvelopedObject() async throws {
            try prepare(statusCode: 200, fixture: .brandingGetCustom)

            let branding = try await makeClient().fetchBranding(serverURL)

            try expectRequest(.get, "/api/branding")
            #expect(branding == Branding(appName: Constants.appName, appLogoUrl: Constants.logoPath))
        }

        @Test
        func updateBrandingPatchesTheNestedBrandingObjectAndReturnsTheEcho() async throws {
            try prepare(statusCode: 200, fixture: .brandingSettingsCustom)

            let branding = try await makeClient().updateBranding(serverURL, Constants.appName, Constants.logoPath)

            try expectRequest(.patch, "/api/settings")
            try expectJSONBody(["branding": ["appName": Constants.appName, "appLogoUrl": Constants.logoPath]])
            #expect(branding == Branding(appName: Constants.appName, appLogoUrl: Constants.logoPath))
        }

        @Test
        func updateBrandingFailsWhenTheEchoCarriesNoBranding() async throws {
            try prepare(statusCode: 200, fixture: .commonEmptyObject)

            await #expect(throws: FilesClientError.decoding("Settings response carried no branding.")) {
                _ = try await makeClient().updateBranding(serverURL, Constants.appName, Constants.logoPath)
            }
        }

        @Test
        func updateBrandingSurfacesTheAdminRequiredReason() async throws {
            try prepare(statusCode: 403, fixture: .systemSettingsErrorAdminRequired)

            await #expect(throws: FilesClientError.forbidden(message: "Admin access required for system settings.")) {
                _ = try await makeClient().updateBranding(serverURL, Constants.appName, Constants.logoPath)
            }
        }

        // MARK: uploadServerLogo

        @Test
        func uploadServerLogoPostsAMultipartLogoFieldAndReturnsTheStoredPath() async throws {
            try prepare(statusCode: 200, fixture: .brandingLogoUploaded)

            let logoURL = try await makeClient().uploadServerLogo(serverURL, Data(Constants.logoBytes.utf8))

            try expectRequest(.post, "/api/settings/upload-logo")
            #expect(logoURL == Constants.logoPath)
            let request = try #require(StubURLProtocol.capturedRequest)
            let contentType = try #require(request.value(forHTTPHeaderField: HTTPHeaderField.contentType))
            let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
            #expect(contentType == MIMEType.multipartFormData(boundary: boundary))
            let body = try String(decoding: #require(StubURLProtocol.capturedRequestBody), as: UTF8.self)
            let expected = "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"logo\"; filename=\"logo.jpg\"\r\n"
                + "Content-Type: image/jpeg\r\n\r\n"
                + Constants.logoBytes
                + "\r\n--\(boundary)--\r\n"
            #expect(body == expected)
        }

        @Test
        func uploadServerLogoAcceptsExactlyTheSizeLimit() async throws {
            try prepare(statusCode: 200, fixture: .brandingLogoUploaded)

            let logoURL = try await makeClient().uploadServerLogo(serverURL, Data(count: Constants.maxLogoBytes))

            #expect(logoURL == Constants.logoPath)
            #expect(StubURLProtocol.requests.count == 1)
        }

        @Test
        func uploadServerLogoRefusesOneByteOverTheLimitWithoutSendingAnything() async throws {
            try prepare(statusCode: 200, fixture: .brandingLogoUploaded)

            await #expect(throws: FilesClientError.decoding("Logo image exceeds the 2 MB limit.")) {
                _ = try await makeClient().uploadServerLogo(serverURL, Data(count: Constants.maxLogoBytes + 1))
            }
            #expect(StubURLProtocol.requests.isEmpty)
        }

        @Test
        func uploadServerLogoSurfacesTheServersRejection() async throws {
            try prepare(statusCode: 400, fixture: .brandingErrorLogoRejected)

            await #expect(throws: FilesClientError.serverMessage(statusCode: 400, message: "Logo must be an image.")) {
                _ = try await makeClient().uploadServerLogo(serverURL, Data(Constants.logoBytes.utf8))
            }
        }

        // MARK: thumbnail settings echo

        @Test
        func updateThumbnailSettingsFailsWhenTheEchoCarriesNoThumbnails() async throws {
            try prepare(statusCode: 200, fixture: .commonEmptyObject)

            await #expect(throws: FilesClientError.decoding("Settings response carried no thumbnails.")) {
                _ = try await makeClient().updateThumbnailSettings(
                    serverURL, ThumbnailSettings(isEnabled: true, size: 128, quality: 50, concurrency: 2)
                )
            }
        }
    }
}
