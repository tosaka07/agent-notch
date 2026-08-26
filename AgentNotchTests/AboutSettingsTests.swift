import Foundation
import Testing

@testable import AgentNotch

@Suite("About settings")
struct AboutSettingsTests {
    @Test("App version reads the short version and build number")
    func appVersionReadsBundleMetadata() {
        let info = AppVersionInfo(
            infoDictionary: [
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "45",
            ]
        )

        #expect(info.version == "1.2.3")
        #expect(info.build == "45")
    }

    @Test("Missing or empty version values remain absent")
    func missingVersionValuesRemainAbsent() {
        let info = AppVersionInfo(
            infoDictionary: [
                "CFBundleShortVersionString": "",
                "CFBundleVersion": 45,
            ]
        )

        #expect(info.version == nil)
        #expect(info.build == nil)
    }

    @Test("Every listed dependency bundles its full license text")
    func everyDependencyBundlesLicenseText() throws {
        for license in OpenSourceLicenseCatalog.licenses {
            let text = try #require(
                license.licenseText(),
                "Missing bundled license text for \(license.name)"
            )
            #expect(text.count > 500)
        }
    }

    @Test("Displayed dependency versions match Package.resolved")
    func dependencyVersionsMatchPackageResolved() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resolvedData = try Data(
            contentsOf: repositoryRoot.appendingPathComponent("Package.resolved")
        )
        let resolved = try JSONDecoder().decode(ResolvedPackage.self, from: resolvedData)
        let versions = Dictionary(
            uniqueKeysWithValues: resolved.pins.compactMap { pin in
                pin.state.version.map { (pin.identity, $0) }
            }
        )
        let compilerOnlyPackages: Set<String> = ["swift-syntax"]
        let runtimePackageIDs = Set(versions.keys).subtracting(compilerOnlyPackages)
        let displayedPackageIDs = Set(OpenSourceLicenseCatalog.licenses.map(\.id))

        for license in OpenSourceLicenseCatalog.licenses {
            #expect(
                versions[license.id] == license.version,
                "Update the About license version for \(license.name)"
            )
        }
        #expect(
            displayedPackageIDs == runtimePackageIDs,
            "Add or remove About licenses when runtime dependencies change"
        )
    }
}

private struct ResolvedPackage: Decodable {
    let pins: [Pin]

    struct Pin: Decodable {
        let identity: String
        let state: State
    }

    struct State: Decodable {
        let version: String?
    }
}
