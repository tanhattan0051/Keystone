// UpdateCheck.swift — pure, testable core of the self-contained auto-updater
// (Phase 5, no Sparkle / no Apple Developer account). See DECISIONS.md
// "Auto-update (Phase 5, no Apple account)" for the full design.
//
// Everything in this file is a pure value type or a pure function: no
// networking, no filesystem, no `Bundle.main`. The app-layer glue that calls
// this (URLSession fetch, `NSAlert` prompts, unzip/relaunch via `Process`)
// lives in App/Updater.swift and is integration-only, same reasoning as the
// CGEventTap itself — see the existing "Integration-only" notes elsewhere in
// DECISIONS.md.

import Foundation
import CryptoKit

/// A parsed `MAJOR.MINOR.PATCH` version, e.g. from a GitHub release tag
/// (`vMAJOR.MINOR.PATCH`) or `CFBundleShortVersionString`.
public struct SemVer: Comparable, Equatable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses a string that may have a leading `v`/`V` ("v1.2.3" or
    /// "1.2.3"). Any pre-release/build-metadata suffix ("-beta.1",
    /// "+build.5") is dropped gracefully rather than rejected. Returns `nil`
    /// for anything that isn't exactly three non-negative integer
    /// components — never crashes on malformed input.
    public init?(_ s: String) {
        var body = s
        if body.hasPrefix("v") || body.hasPrefix("V") {
            body.removeFirst()
        }
        if let suffixStart = body.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            body = String(body[body.startIndex..<suffixStart])
        }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard
            let major = Int(parts[0]), major >= 0,
            let minor = Int(parts[1]), minor >= 0,
            let patch = Int(parts[2]), patch >= 0
        else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The pieces of a GitHub "latest release" response the updater needs:
/// the version it's tagged with, and the two asset URLs it must download.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemVer
    public let zipURL: URL
    public let signatureURL: URL

    public init(version: SemVer, zipURL: URL, signatureURL: URL) {
        self.version = version
        self.zipURL = zipURL
        self.signatureURL = signatureURL
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: String

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [GitHubAsset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    /// Decodes a GitHub "latest release" API response. Requires a
    /// `Keystone.zip` asset AND a `Keystone.zip.sig` asset AND a parseable
    /// `tag_name` — missing or malformed input (including JSON that doesn't
    /// even parse) returns `nil` rather than crashing, per the boundary rule:
    /// validate everything that comes from the network before trusting it.
    /// Also rejects any asset URL that isn't `https://` — this app only ever
    /// fetches updates over HTTPS, so a scheme downgrade (however unlikely
    /// from the real GitHub API) is treated the same as a missing asset.
    public static func parse(latestReleaseJSON data: Data) -> ReleaseInfo? {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            return nil
        }
        guard let version = SemVer(release.tagName) else { return nil }
        guard
            let zipAsset = release.assets.first(where: { $0.name == "Keystone.zip" }),
            let sigAsset = release.assets.first(where: { $0.name == "Keystone.zip.sig" }),
            let zipURL = URL(string: zipAsset.browserDownloadURL),
            let signatureURL = URL(string: sigAsset.browserDownloadURL),
            zipURL.scheme == "https",
            signatureURL.scheme == "https"
        else {
            return nil
        }
        return ReleaseInfo(version: version, zipURL: zipURL, signatureURL: signatureURL)
    }
}

/// Verifies a downloaded update against the embedded Ed25519 public key.
/// This is the mandatory, non-bypassable security gate for the whole
/// feature: an update is downloaded from the internet and then executed, so
/// it MUST be verified before it is ever unzipped-into-place or launched.
/// See App/Updater.swift's `downloadAndInstall` for the call site — the
/// `guard UpdateVerifier.isValid(...) else { abort }` there is what this
/// type exists to make possible.
public enum UpdateVerifier {
    /// Returns whether `signatureBase64` is a valid Ed25519 signature of
    /// `zipData` under `publicKeyBase64`. Any decode failure (bad base64,
    /// wrong-length key, corrupt signature) returns `false` — this never
    /// throws into the caller, so a malformed or missing signature always
    /// reads as "not verified" rather than crashing the updater.
    public static func isValid(zipData: Data, signatureBase64: String, publicKeyBase64: String) -> Bool {
        guard
            let signature = Data(base64Encoded: signatureBase64),
            let keyBytes = Data(base64Encoded: publicKeyBase64)
        else {
            return false
        }
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: zipData)
    }
}

/// Version-comparison helpers the app layer uses to decide whether to
/// prompt for an update.
public enum UpdateCheck {
    public static func isNewer(_ candidate: SemVer, than current: SemVer) -> Bool {
        candidate > current
    }

    /// Given the running app's version string (from
    /// `CFBundleShortVersionString`) and the parsed latest release, decides
    /// whether the app should offer to update. A `currentVersion` that fails
    /// to parse is treated as "don't offer" — safer than assuming every
    /// release is newer than a version we couldn't even read.
    public static func shouldOffer(currentVersion: String, release: ReleaseInfo) -> Bool {
        guard let current = SemVer(currentVersion) else { return false }
        return isNewer(release.version, than: current)
    }
}

/// Upper bounds for what the updater will accept from the network, so a
/// hostile or broken server cannot make the app swallow unbounded data
/// before the signature gate even runs.
public enum UpdateLimits {
    public static let maxZipBytes = 64 * 1024 * 1024
    public static let maxSignatureBytes = 1024

    /// `expectedContentLength` is the server's claim (`nil` or negative =
    /// unknown, as `URLResponse` reports -1); `byteCount` is what actually
    /// arrived. Both are checked because the header can lie.
    public static func isAcceptable(byteCount: Int64, expectedContentLength: Int64?, limit: Int) -> Bool {
        let limit = Int64(limit)
        if let expected = expectedContentLength, expected >= 0, expected > limit {
            return false
        }
        return byteCount <= limit
    }
}

/// Outcome of inspecting the `Info.plist` of an extracted update bundle.
public enum StagedBundleCheck: Equatable, Sendable {
    case ok
    case wrongBundleIdentifier(found: String?)
    case unreadableVersion(found: String?)
    case versionMismatch(expected: SemVer, found: SemVer)
    case notNewer(current: SemVer, found: SemVer)

    /// Short Vietnamese text for the app alert. Empty for `.ok`.
    public var userMessage: String {
        switch self {
        case .ok:
            return ""
        case .wrongBundleIdentifier:
            return "Bản tải về không phải Keystone (sai mã định danh ứng dụng) — đã huỷ để an toàn"
        case .unreadableVersion:
            return "Không đọc được số phiên bản của bản tải về — đã huỷ để an toàn"
        case .versionMismatch(let expected, let found):
            return "Bản tải về là v\(found) nhưng bản phát hành công bố v\(expected) — đã huỷ để an toàn"
        case .notNewer(let current, let found):
            return "Bản tải về (v\(found)) không mới hơn bản đang dùng (v\(current)) — đã huỷ"
        }
    }
}

extension UpdateCheck {
    /// The Ed25519 signature only proves the zip was once genuinely signed,
    /// not that it is the build the release tag advertises. So the unpacked
    /// bundle's own identity is cross-checked against the offered release:
    /// a replayed OLD signed zip under a NEWER tag fails `versionMismatch`.
    /// Order: bundle id (exact) -> version parses -> equals offered -> newer
    /// than the running version.
    public static func validateStagedBundle(
        bundleIdentifier: String?,
        shortVersion: String?,
        expectedBundleIdentifier: String,
        offeredVersion: SemVer,
        currentVersion: SemVer
    ) -> StagedBundleCheck {
        guard bundleIdentifier == expectedBundleIdentifier else {
            return .wrongBundleIdentifier(found: bundleIdentifier)
        }
        guard let shortVersion, let found = SemVer(shortVersion) else {
            return .unreadableVersion(found: shortVersion)
        }
        guard found == offeredVersion else {
            return .versionMismatch(expected: offeredVersion, found: found)
        }
        guard found > currentVersion else {
            return .notNewer(current: currentVersion, found: found)
        }
        return .ok
    }
}
