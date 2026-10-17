// Updater.swift — self-contained auto-updater: pulls signed updates from
// this app's GitHub Releases. No Sparkle, no Apple Developer account (see
// DECISIONS.md "Auto-update (Phase 5, no Apple account)").
//
// The pure, unit-tested logic (SemVer, ReleaseInfo.parse, UpdateVerifier,
// UpdateCheck) lives in Sources/KeystoneInput/UpdateCheck.swift. Everything
// here is integration glue — URLSession, NSAlert, Process — and is not
// unit-testable headless, same reasoning as the CGEventTap itself.
//
// SECURITY: an update is downloaded from the internet and then EXECUTED.
// `downloadAndInstall` verifies it with the embedded Ed25519 public key
// BEFORE it is ever unzipped-into-place or launched. That `guard
// UpdateVerifier.isValid(...)` is the mandatory, non-bypassable gate for the
// whole feature — see the comment at its call site below.
//
// INSTALL FLOW (after the signature gate): unzip into a work dir, then
// cross-check the extracted bundle against the offered release (bundle id,
// version == tag, version > running — the signature alone cannot stop a
// replayed OLD signed zip under a NEWER tag), `codesign --verify`, strip
// quarantine, make sure the install folder is writable, write the helper
// script INTO the work dir and launch it detached, and only then quit. The
// script (UpdateInstallScript) waits for us to exit, copies the new bundle
// next to the installed one, re-verifies it, swaps with two renames, and
// rolls back + relaunches the old bundle on any failure. Log:
// ~/Library/Logs/Keystone/update.log.

import Foundation
import AppKit
import os
import KeystoneInput

@MainActor
final class Updater {
    static let shared = Updater()
    private static let log = Logger(subsystem: "com.tanta.keystone", category: "Updater")

    /// Hardcoded, case-sensitive repo — the only source this updater will
    /// ever fetch from.
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/tanhattan0051/Keystone/releases/latest")!

    /// Embedded Ed25519 public key (base64, 32 raw bytes) used to verify
    /// every downloaded update. There is no code path that installs an
    /// update without passing `UpdateVerifier.isValid` against this key.
    private static let embeddedPublicKeyBase64 = "MJ8bmdlgJFAYi+M4+Hm3g+phMGDE+lamYdN3DPuiuvA="

    private init() {}

    /// Entry point. Safe to call from a UI button (`userInitiated: true`) or
    /// a silent background check at launch (`userInitiated: false`) — kicks
    /// off its own `Task` and returns immediately either way.
    func checkForUpdates(userInitiated: Bool) {
        guard
            let currentVersionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            SemVer(currentVersionString) != nil
        else {
            // Auto-update only makes sense for an installed .app — running
            // via `swift run` has no meaningful CFBundleShortVersionString.
            if userInitiated {
                showAlert("Đang chạy bản dev (swift run) — không kiểm tra cập nhật được")
            }
            return
        }

        Task { [weak self] in
            await self?.performCheck(currentVersion: currentVersionString, userInitiated: userInitiated)
        }
    }

    private func performCheck(currentVersion: String, userInitiated: Bool) async {
        var request = URLRequest(url: Self.latestReleaseAPIURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Keystone/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            data = responseData
        } catch {
            Self.log.error("Latest-release request failed: \(error.localizedDescription, privacy: .public)")
            if userInitiated {
                showAlert("Không kiểm tra được bản cập nhật", informativeText: error.localizedDescription)
            }
            return
        }

        guard
            let currentSemVer = SemVer(currentVersion),
            let release = ReleaseInfo.parse(latestReleaseJSON: data)
        else {
            Self.log.error("Latest-release response could not be parsed (missing tag/assets or malformed JSON)")
            if userInitiated {
                showAlert("Không kiểm tra được bản cập nhật", informativeText: "Không đọc được thông tin bản phát hành từ GitHub.")
            }
            return
        }

        guard UpdateCheck.shouldOffer(currentVersion: currentVersion, release: release) else {
            if userInitiated {
                showAlert("Bạn đang dùng bản mới nhất (v\(currentVersion))", style: .informational)
            }
            return
        }

        promptToInstall(release, currentVersion: currentSemVer)
    }

    private func promptToInstall(_ release: ReleaseInfo, currentVersion: SemVer) {
        let alert = NSAlert()
        alert.messageText = "Có bản mới v\(release.version). Cập nhật ngay?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cập nhật")
        alert.addButton(withTitle: "Để sau")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { [weak self] in
            await self?.downloadAndInstall(release, currentVersion: currentVersion)
        }
    }

    private func downloadAndInstall(_ info: ReleaseInfo, currentVersion: SemVer) async {
        let zipData: Data
        let signatureBase64: String
        do {
            zipData = try await fetchData(from: info.zipURL, timeout: 120)
            let signatureData = try await fetchData(from: info.signatureURL, timeout: 30)
            guard let decoded = String(data: signatureData, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            signatureBase64 = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Self.log.error("Update download failed: \(error.localizedDescription, privacy: .public)")
            showAlert("Tải bản cập nhật thất bại", informativeText: error.localizedDescription)
            return
        }

        // MANDATORY SECURITY GATE — non-bypassable. A downloaded update is
        // about to be unzipped-into-place and executed; it must never
        // install without a valid Ed25519 signature under the embedded
        // public key. Any failure here aborts and tells the user why.
        guard UpdateVerifier.isValid(
            zipData: zipData,
            signatureBase64: signatureBase64,
            publicKeyBase64: Self.embeddedPublicKeyBase64
        ) else {
            Self.log.error("Update signature verification FAILED — install aborted")
            showAlert("Chữ ký bản cập nhật không hợp lệ — đã huỷ để an toàn")
            return
        }

        do {
            try installVerifiedUpdate(zipData: zipData, release: info, currentVersion: currentVersion)
        } catch {
            Self.log.error("Update install failed: \(error.localizedDescription, privacy: .public)")
            showAlert("Cài đặt cập nhật thất bại", informativeText: error.localizedDescription)
        }
    }

    private func fetchData(from url: URL, timeout: TimeInterval) async throws -> Data {
        let request = URLRequest(url: url, timeoutInterval: timeout)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// `zipData` has ALREADY passed `UpdateVerifier.isValid` by the time this
    /// is called — never call this on unverified bytes. Quits the app only
    /// after the install helper has launched; any earlier failure removes the
    /// work dir and leaves the running app untouched.
    private func installVerifiedUpdate(zipData: Data, release: ReleaseInfo, currentVersion: SemVer) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("KeystoneUpdate-\(UUID().uuidString)", isDirectory: true)

        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
            try stageAndLaunchInstallHelper(zipData: zipData, release: release, currentVersion: currentVersion, workDir: workDir)
        } catch {
            removeWorkDir(workDir)
            throw error
        }

        Self.log.info("Update verified and staged; quitting so the install helper can swap the bundle")
        AppModel.shared.quit()
    }

    /// Unzips, validates the extracted bundle and launches the detached
    /// install script. Throws before launching if anything is off.
    private func stageAndLaunchInstallHelper(zipData: Data, release: ReleaseInfo, currentVersion: SemVer, workDir: URL) throws {
        let fm = FileManager.default

        let zipPath = workDir.appendingPathComponent("Keystone.zip")
        do {
            try zipData.write(to: zipPath)
        } catch {
            throw UpdaterError.cannotWriteTempFile(error.localizedDescription)
        }

        let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", ["-x", "-k", zipPath.path, extractDir.path])

        guard let extractedApp = try findKeystoneApp(in: extractDir) else {
            throw UpdaterError.appNotFoundInDownload
        }

        // The signature only proves the zip was once genuinely signed; check
        // the bundle really is the build this release advertises (blocks a
        // replayed old signed zip served under a newer tag).
        guard let expectedBundleIdentifier = Bundle.main.bundleIdentifier else {
            throw UpdaterError.currentBundleNotFound
        }
        let staged = try readStagedInfo(of: extractedApp)
        let check = UpdateCheck.validateStagedBundle(
            bundleIdentifier: staged.bundleIdentifier,
            shortVersion: staged.shortVersion,
            expectedBundleIdentifier: expectedBundleIdentifier,
            offeredVersion: release.version,
            currentVersion: currentVersion
        )
        guard check == .ok else {
            Self.log.error("Staged bundle rejected: \(String(describing: check), privacy: .public)")
            throw UpdaterError.stagedBundleRejected(check.userMessage)
        }

        try runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", extractedApp.path])

        try runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", extractedApp.path])

        let currentBundleURL = Bundle.main.bundleURL
        guard currentBundleURL.pathExtension == "app" else {
            throw UpdaterError.currentBundleNotFound
        }

        // The script renames siblings next to the installed bundle, so that
        // folder must be writable. Checked BEFORE quitting: an app
        // translocated by Gatekeeper or sitting in a root-owned folder can't
        // be updated, and the user must not lose the running app for it.
        let installFolder = currentBundleURL.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: installFolder.path) else {
            throw UpdaterError.installFolderNotWritable(installFolder.path)
        }

        try launchInstallHelper(newAppPath: extractedApp.path, installedAppPath: currentBundleURL.path, expectedBundleIdentifier: expectedBundleIdentifier, expectedVersion: release.version, workDir: workDir)
    }

    /// Reads Info.plist directly (not `Bundle(url:)`, which caches).
    private func readStagedInfo(of app: URL) throws -> (bundleIdentifier: String?, shortVersion: String?) {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        let data: Data
        do {
            data = try Data(contentsOf: plistURL)
        } catch {
            throw UpdaterError.stagedBundleRejected("Không đọc được Info.plist của bản tải về: \(error.localizedDescription)")
        }
        let object = try? PropertyListSerialization.propertyList(from: data, format: nil)
        guard let plist = object as? [String: Any] else {
            throw UpdaterError.stagedBundleRejected("Info.plist của bản tải về không hợp lệ")
        }
        return (plist["CFBundleIdentifier"] as? String, plist["CFBundleShortVersionString"] as? String)
    }

    private func removeWorkDir(_ workDir: URL) {
        do {
            try FileManager.default.removeItem(at: workDir)
        } catch {
            Self.log.error("Could not remove update work dir \(workDir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func findKeystoneApp(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents.first { $0.lastPathComponent == "Keystone.app" }
    }

    /// Writes the install script INTO the work dir (so its own cleanup
    /// removes it too) and launches it detached via `Process` so it keeps
    /// running after this process quits. The script itself waits for this
    /// process to exit (a running bundle can't be replaced), swaps
    /// atomically and rolls back on failure — see UpdateInstallScript.
    private func launchInstallHelper(newAppPath: String, installedAppPath: String, expectedBundleIdentifier: String, expectedVersion: SemVer, workDir: URL) throws {
        let fm = FileManager.default
        guard let libraryDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw UpdaterError.cannotWriteTempFile("không tìm thấy thư mục Library")
        }
        let logFile = libraryDir.appendingPathComponent("Logs/Keystone/update.log")

        let script = UpdateInstallScript.make(
            waitForPID: ProcessInfo.processInfo.processIdentifier,
            stagedAppPath: newAppPath,
            installedAppPath: installedAppPath,
            workDirPath: workDir.path,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedVersion: expectedVersion.description,
            logFilePath: logFile.path
        )

        let scriptURL = workDir.appendingPathComponent("install.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        } catch {
            throw UpdaterError.cannotWriteTempFile(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdaterError.processLaunchFailed("/bin/bash", error.localizedDescription)
        }
    }

    @discardableResult
    private func runProcess(_ executablePath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw UpdaterError.processLaunchFailed(executablePath, error.localizedDescription)
        }
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            Self.log.error("\(executablePath, privacy: .public) exited \(process.terminationStatus): \(output, privacy: .public)")
            throw UpdaterError.processExitedNonZero(executablePath, process.terminationStatus, output)
        }
        return output
    }

    private func showAlert(_ messageText: String, informativeText: String? = nil, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = messageText
        if let informativeText {
            alert.informativeText = informativeText
        }
        alert.alertStyle = style
        alert.runModal()
    }
}

private enum UpdaterError: LocalizedError {
    case cannotWriteTempFile(String)
    case processLaunchFailed(String, String)
    case processExitedNonZero(String, Int32, String)
    case appNotFoundInDownload
    case currentBundleNotFound
    case stagedBundleRejected(String)
    case installFolderNotWritable(String)

    var errorDescription: String? {
        switch self {
        case .stagedBundleRejected(let message):
            return message
        case .installFolderNotWritable(let path):
            return "Không ghi được vào thư mục \(path) (ứng dụng đang chạy từ vị trí tạm hoặc thư mục cần quyền quản trị). Hãy cập nhật thủ công: tải Keystone mới và kéo vào Applications."
        case .cannotWriteTempFile(let reason):
            return "Không ghi được file tạm: \(reason)"
        case .processLaunchFailed(let command, let reason):
            return "Không chạy được lệnh \(command): \(reason)"
        case .processExitedNonZero(let command, let code, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Lệnh \(command) thất bại (mã \(code))"
                : "Lệnh \(command) thất bại (mã \(code)): \(trimmed)"
        case .appNotFoundInDownload:
            return "Không tìm thấy Keystone.app trong bản tải về"
        case .currentBundleNotFound:
            return "Không xác định được vị trí ứng dụng Keystone hiện tại"
        }
    }
}
