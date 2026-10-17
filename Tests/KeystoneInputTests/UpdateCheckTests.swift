// UpdateCheckTests.swift — pins the pure logic behind the self-contained
// GitHub-Releases auto-updater (Phase 5, DECISIONS.md "Auto-update").
//
// Everything under test here is pure: no network, no filesystem, no
// `Bundle.main`. The `Updater` app-layer glue (App/Updater.swift) that wires
// this to `URLSession`/`Process`/`NSAlert` is integration-only and not
// unit-testable headless, same reasoning as the CGEventTap itself.

import Testing
import Foundation
import CryptoKit
@testable import KeystoneInput

@Suite("SemVer")
struct SemVerTests {
    @Test func parsesWithLeadingV() {
        #expect(SemVer("v1.2.3") == SemVer(major: 1, minor: 2, patch: 3))
    }

    @Test func parsesWithoutLeadingV() {
        #expect(SemVer("1.0.0") == SemVer(major: 1, minor: 0, patch: 0))
    }

    @Test func dropsPreReleaseSuffixGracefully() {
        #expect(SemVer("v1.2.3-beta.1") == SemVer(major: 1, minor: 2, patch: 3))
        #expect(SemVer("1.2.3+build.5") == SemVer(major: 1, minor: 2, patch: 3))
    }

    @Test func rejectsGarbage() {
        #expect(SemVer("not-a-version") == nil)
        #expect(SemVer("1.2") == nil)
        #expect(SemVer("") == nil)
        #expect(SemVer("v") == nil)
        #expect(SemVer("1.2.3.4") == nil)
        #expect(SemVer("1.x.3") == nil)
    }

    @Test func ordering() {
        #expect(SemVer("1.0.0")! < SemVer("1.0.1")!)
        #expect(SemVer("1.0.1")! < SemVer("1.1.0")!)
        #expect(SemVer("1.1.0")! < SemVer("2.0.0")!)
        #expect(SemVer("2.0.0")! > SemVer("1.9.9")!)
    }

    @Test func descriptionRoundTrips() {
        #expect(SemVer(major: 1, minor: 2, patch: 3).description == "1.2.3")
    }

    @Test func equalVersionsAreNotNewer() {
        let a = SemVer("1.0.0")!
        let b = SemVer("1.0.0")!
        #expect(UpdateCheck.isNewer(a, than: b) == false)
    }
}

@Suite("ReleaseInfo.parse")
struct ReleaseInfoParseTests {
    private func json(tag: String?, assets: [(name: String, url: String)]) -> Data {
        var assetsJSON = "["
        assetsJSON += assets.map { "{\"name\": \"\($0.name)\", \"browser_download_url\": \"\($0.url)\"}" }
            .joined(separator: ", ")
        assetsJSON += "]"
        var fields: [String] = []
        if let tag { fields.append("\"tag_name\": \"\(tag)\"") }
        fields.append("\"assets\": \(assetsJSON)")
        // Extra, unrelated fields a real GitHub payload carries — parse must
        // ignore them rather than choke on unexpected JSON.
        fields.append("\"draft\": false")
        fields.append("\"prerelease\": false")
        fields.append("\"html_url\": \"https://github.com/tanhattan0051/Keystone/releases/tag/v1.0.1\"")
        return Data("{\(fields.joined(separator: ", "))}".utf8)
    }

    private let zipURL = "https://github.com/tanhattan0051/Keystone/releases/download/v1.0.1/Keystone.zip"
    private let sigURL = "https://github.com/tanhattan0051/Keystone/releases/download/v1.0.1/Keystone.zip.sig"

    @Test func parsesValidPayload() {
        let data = json(tag: "v1.0.1", assets: [
            ("Keystone.zip", zipURL),
            ("Keystone.zip.sig", sigURL),
        ])
        let info = ReleaseInfo.parse(latestReleaseJSON: data)
        #expect(info?.version == SemVer(major: 1, minor: 0, patch: 1))
        #expect(info?.zipURL == URL(string: zipURL))
        #expect(info?.signatureURL == URL(string: sigURL))
    }

    @Test func missingSignatureAssetIsNil() {
        let data = json(tag: "v1.0.1", assets: [("Keystone.zip", zipURL)])
        #expect(ReleaseInfo.parse(latestReleaseJSON: data) == nil)
    }

    @Test func missingZipAssetIsNil() {
        let data = json(tag: "v1.0.1", assets: [("Keystone.zip.sig", sigURL)])
        #expect(ReleaseInfo.parse(latestReleaseJSON: data) == nil)
    }

    @Test func missingTagIsNil() {
        let data = json(tag: nil, assets: [
            ("Keystone.zip", zipURL),
            ("Keystone.zip.sig", sigURL),
        ])
        #expect(ReleaseInfo.parse(latestReleaseJSON: data) == nil)
    }

    @Test func unparseableTagIsNil() {
        let data = json(tag: "not-a-semver", assets: [
            ("Keystone.zip", zipURL),
            ("Keystone.zip.sig", sigURL),
        ])
        #expect(ReleaseInfo.parse(latestReleaseJSON: data) == nil)
    }

    @Test func nonHTTPSAssetURLIsNil() {
        let data = json(tag: "v1.0.1", assets: [
            ("Keystone.zip", "http://github.com/tanhattan0051/Keystone/releases/download/v1.0.1/Keystone.zip"),
            ("Keystone.zip.sig", sigURL),
        ])
        #expect(ReleaseInfo.parse(latestReleaseJSON: data) == nil)
    }

    @Test func malformedJSONIsNil() {
        let data = Data("{ this is not json".utf8)
        #expect(ReleaseInfo.parse(latestReleaseJSON: data) == nil)
    }

    @Test func emptyDataIsNil() {
        #expect(ReleaseInfo.parse(latestReleaseJSON: Data()) == nil)
    }
}

@Suite("UpdateVerifier")
struct UpdateVerifierTests {
    /// Round-trip: sign real bytes with a freshly generated key, then assert
    /// `isValid` accepts the right (data, sig, pubkey) triple and rejects
    /// every tampered variant. This is the test that actually exercises the
    /// mandatory security gate — see App/Updater.swift's `downloadAndInstall`.
    @Test func acceptsGenuineSignature() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let data = Data("Keystone.zip bytes go here".utf8)
        let signature = try! privateKey.signature(for: data)
        let sigBase64 = signature.base64EncodedString()
        let pubBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

        #expect(UpdateVerifier.isValid(zipData: data, signatureBase64: sigBase64, publicKeyBase64: pubBase64))
    }

    @Test func rejectsTamperedData() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let data = Data("Keystone.zip bytes go here".utf8)
        let signature = try! privateKey.signature(for: data)
        let sigBase64 = signature.base64EncodedString()
        let pubBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

        let tampered = Data("Keystone.zip BYTES go here".utf8)
        #expect(UpdateVerifier.isValid(zipData: tampered, signatureBase64: sigBase64, publicKeyBase64: pubBase64) == false)
    }

    @Test func rejectsWrongPublicKey() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let wrongKey = Curve25519.Signing.PrivateKey()
        let data = Data("Keystone.zip bytes go here".utf8)
        let signature = try! privateKey.signature(for: data)
        let sigBase64 = signature.base64EncodedString()
        let wrongPubBase64 = wrongKey.publicKey.rawRepresentation.base64EncodedString()

        #expect(UpdateVerifier.isValid(zipData: data, signatureBase64: sigBase64, publicKeyBase64: wrongPubBase64) == false)
    }

    @Test func rejectsGarbageSignatureBase64() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let data = Data("Keystone.zip bytes go here".utf8)
        let pubBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

        #expect(UpdateVerifier.isValid(zipData: data, signatureBase64: "not-base64-!!!", publicKeyBase64: pubBase64) == false)
    }

    @Test func rejectsGarbagePublicKeyBase64() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let data = Data("Keystone.zip bytes go here".utf8)
        let signature = try! privateKey.signature(for: data)
        let sigBase64 = signature.base64EncodedString()

        #expect(UpdateVerifier.isValid(zipData: data, signatureBase64: sigBase64, publicKeyBase64: "not-base64-!!!") == false)
    }

    @Test func rejectsWrongLengthPublicKey() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let data = Data("Keystone.zip bytes go here".utf8)
        let signature = try! privateKey.signature(for: data)
        let sigBase64 = signature.base64EncodedString()
        // Valid base64, but not 32 raw bytes — must not throw into the caller.
        let shortKeyBase64 = Data([0x01, 0x02, 0x03]).base64EncodedString()

        #expect(UpdateVerifier.isValid(zipData: data, signatureBase64: sigBase64, publicKeyBase64: shortKeyBase64) == false)
    }
}

@Suite("UpdateCheck.shouldOffer")
struct UpdateCheckShouldOfferTests {
    private func release(_ version: String) -> ReleaseInfo {
        ReleaseInfo(
            version: SemVer(version)!,
            zipURL: URL(string: "https://example.com/Keystone.zip")!,
            signatureURL: URL(string: "https://example.com/Keystone.zip.sig")!
        )
    }

    @Test func offersWhenReleaseIsNewer() {
        #expect(UpdateCheck.shouldOffer(currentVersion: "1.0.0", release: release("1.0.1")))
    }

    @Test func doesNotOfferWhenUpToDate() {
        #expect(UpdateCheck.shouldOffer(currentVersion: "1.0.1", release: release("1.0.1")) == false)
    }

    @Test func doesNotOfferWhenReleaseIsOlder() {
        #expect(UpdateCheck.shouldOffer(currentVersion: "2.0.0", release: release("1.9.9")) == false)
    }

    @Test func doesNotOfferWhenCurrentVersionIsUnparseable() {
        #expect(UpdateCheck.shouldOffer(currentVersion: "dev-build", release: release("1.0.0")) == false)
    }
}

@Suite("UpdateCheck.validateStagedBundle")
struct StagedBundleValidationTests {
    private let bundleID = "com.tanta.keystone"
    private let current = SemVer(major: 1, minor: 1, patch: 8)
    private let offered = SemVer(major: 1, minor: 2, patch: 0)

    private func validate(id: String? = "com.tanta.keystone", version: String? = "1.2.0") -> StagedBundleCheck {
        UpdateCheck.validateStagedBundle(
            bundleIdentifier: id,
            shortVersion: version,
            expectedBundleIdentifier: bundleID,
            offeredVersion: offered,
            currentVersion: current
        )
    }

    @Test func okWhenIdentifierAndVersionMatchAndNewer() {
        #expect(validate() == .ok)
    }

    @Test func wrongBundleIdentifier() {
        #expect(validate(id: "com.evil.app") == .wrongBundleIdentifier(found: "com.evil.app"))
        #expect(validate(id: "com.tanta.Keystone") == .wrongBundleIdentifier(found: "com.tanta.Keystone"))
    }

    @Test func nilBundleIdentifierIsWrong() {
        #expect(validate(id: nil) == .wrongBundleIdentifier(found: nil))
    }

    @Test func bundleIdentifierIsCheckedBeforeVersion() {
        #expect(validate(id: "x", version: nil) == .wrongBundleIdentifier(found: "x"))
    }

    @Test func nilOrGarbageVersionIsUnreadable() {
        #expect(validate(version: nil) == .unreadableVersion(found: nil))
        #expect(validate(version: "banana") == .unreadableVersion(found: "banana"))
        #expect(validate(version: "1.2") == .unreadableVersion(found: "1.2"))
    }

    @Test func replayedOldBuildUnderNewTagIsVersionMismatch() {
        // Tag says 9.9.9, but the genuinely-signed zip inside is 1.0.0.
        let result = UpdateCheck.validateStagedBundle(
            bundleIdentifier: bundleID,
            shortVersion: "1.0.0",
            expectedBundleIdentifier: bundleID,
            offeredVersion: SemVer(major: 9, minor: 9, patch: 9),
            currentVersion: current
        )
        #expect(result == .versionMismatch(expected: SemVer(major: 9, minor: 9, patch: 9),
                                           found: SemVer(major: 1, minor: 0, patch: 0)))
    }

    @Test func versionMatchingOfferedButNotNewerThanCurrentIsNotNewer() {
        let result = UpdateCheck.validateStagedBundle(
            bundleIdentifier: bundleID,
            shortVersion: "1.1.8",
            expectedBundleIdentifier: bundleID,
            offeredVersion: current,
            currentVersion: current
        )
        #expect(result == .notNewer(current: current, found: current))
    }

    @Test func everyFailureHasAVietnameseMessageAndOkHasNone() {
        let failures: [StagedBundleCheck] = [
            .wrongBundleIdentifier(found: nil),
            .unreadableVersion(found: "x"),
            .versionMismatch(expected: offered, found: current),
            .notNewer(current: current, found: current),
        ]
        for failure in failures {
            #expect(!failure.userMessage.isEmpty)
        }
        #expect(StagedBundleCheck.ok.userMessage.isEmpty)
    }
}
