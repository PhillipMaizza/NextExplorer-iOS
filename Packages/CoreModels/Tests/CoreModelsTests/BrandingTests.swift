@testable import CoreModels
import Foundation
import Testing

@Suite("Branding")
struct BrandingTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    @Test("decodes a full branding object")
    func decodesFullObject() throws {
        let json = #"{"appName": "Rivendell", "appLogoUrl": "/static/logos/custom-logo.png", "showPoweredBy": true}"#
        let branding = try JSONDecoder().decode(Branding.self, from: Data(json.utf8))
        #expect(branding.appName == "Rivendell")
        #expect(branding.appLogoUrl == "/static/logos/custom-logo.png")
    }

    @Test("missing keys fall back to the server's own defaults")
    func missingKeysUseDefaults() throws {
        let branding = try JSONDecoder().decode(Branding.self, from: Data("{}".utf8))
        #expect(branding.appName == "Explorer")
        #expect(branding.appLogoUrl == "/logo.svg")
        #expect(branding.hasCustomLogo == false)
    }

    @Test("the packaged default logo resolves to no URL")
    func defaultLogoHasNoResolvedURL() {
        let branding = Branding()
        #expect(branding.resolvedLogoURL(serverURL: serverURL) == nil)
    }

    @Test("a server-relative custom logo resolves against the server URL")
    func relativeCustomLogoResolves() {
        let branding = Branding(appName: "X", appLogoUrl: "/static/logos/custom-logo.png")
        #expect(branding.hasCustomLogo)
        #expect(branding.resolvedLogoURL(serverURL: serverURL)?.absoluteString
            == "https://cloud.example.com/static/logos/custom-logo.png")
    }

    @Test("an absolute custom logo URL is used as is")
    func absoluteCustomLogoIsUsedVerbatim() {
        let branding = Branding(appName: "X", appLogoUrl: "https://cdn.example.net/logo.png")
        #expect(branding.resolvedLogoURL(serverURL: serverURL)?.absoluteString
            == "https://cdn.example.net/logo.png")
    }
}
