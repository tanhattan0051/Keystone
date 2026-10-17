// Updater.swift — self-contained auto-updater: pulls signed updates from
// this app's GitHub Releases. No Sparkle, no Apple Developer account (see
// DECISIONS.md "Auto-update (Phase 5, no Apple account)").
//
// The pure, unit-tested logic (SemVer, ReleaseInfo.parse, UpdateVerifier,
// UpdateCheck, UpdateLimits) lives in Sources/KeystoneInput/UpdateCheck.swift.
// Everything here is integration glue — URLSession, NSAlert, Process — and is
// not unit-testable headless, same reasoning as the CGEventTap itself.
//
// SECURITY: an update is downloaded from the internet and then EXECUTED.
// `UpdatePipeline.verifyAndStage` verifies it with the embedded Ed25519
// public key BEFORE it is ever unzipped-into-place or launched. That `guard
// UpdateVerifier.isValid(...)` is the mandatory, non-bypassable gate for the
// whole feature — see the comment at its call site below.
//
// THREADING: `Updater` is @MainActor and only does UI (NSAlert), the cheap
// writability check, launching the helper and quitting. All slow work —
// downloads, Ed25519 over the whole zip, `ditto`, `codesign`, `xattr` —
// lives in the nonisolated `UpdatePipeline`, so the menu bar, Control Panel,
// switch-key monitors and AX focus tracking never freeze while it runs. Only
// Sendable values (URLs, strings, SemVer, ReleaseInfo) cross between them.
//
// ORDER OF GATES: download (size-capped) -> Ed25519 verify -> extract ->
// validate plist (bundle id, version == offered, > running) -> codesign
// verify -> strip quarantine -> writability check -> launch helper -> quit.
//
// INSTALL FLOW (after the signature gate): unzip into a work dir, then
// cross-check the extracted bundle against the offered release (the
// signature alone cannot stop a replayed OLD signed zip under a NEWER tag),
// `codesign --verify`, strip quarantine, make sure the install folder is
// writable, write the helper script INTO the work dir and launch it
// detached, and only then quit. The script (UpdateInstallScript) waits for
// us to exit, copies the new bundle next to the installed one, re-verifies
// it, swaps with two renames, and rolls back + relaunches the old bundle on
// any failure. The work dir is removed here on EVERY failure path and by the
// script on the success path. Log: ~/Library/Logs/Keystone/update.log.

import Foundation
import AppKit
import os
import KeystoneInput

private let updaterLog = Logger(subsystem: "com.tanta.keystone", category: "Updater")

@MainActor
final class Updater {
    static let shared = Updater()
    private static let log = updaterLog

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
        // Read main-actor-only state here, hand plain values to the pipeline.
        guard let expectedBundleIdentifier = Bundle.main.bundleIdentifier else {
            showAlert("Cài đặt cập nhật thất bại", informativeText: UpdaterError.currentBundleNotFound.localizedDescription)
            return
        }

        let workDir: URL
        do {
            workDir = try UpdatePipeline.makeWorkDir()
        } catch {
            Self.log.error("Update work dir could not be created: \(error.localizedDescription, privacy: .public)")
            showAlert("Cài đặt cập nhật thất bại", informativeText: error.localizedDescription)
            return
        }

        // From here on, ANY failure removes the work dir. The success path
        // hands it to the install script, which removes it itself.
        var handedOverToInstallScript = false
        defer {
            if !handedOverToInstallScript { UpdatePipeline.removeWorkDir(workDir) }
        }

        let download: DownloadedUpdate
        do {
            download = try await UpdatePipeline.download(release: info, into: workDir)
        } catch {
            Self.log.error("Update download failed: \(error.localizedDescription, privacy: .public)")
            showAlert("Tải bản cập nhật thất bại", informativeText: error.localizedDescription)
            return
        }

        let extractedApp: URL
        do {
            extractedApp = try await UpdatePipeline.verifyAndStage(
                download: download,
                release: info,
                currentVersion: currentVersion,
                expectedBundleIdentifier: expectedBundleIdentifier,
                publicKeyBase64: Self.embeddedPublicKeyBase64
            )
        } catch UpdaterError.signatureInvalid {
            showAlert("Chữ ký bản cập nhật không hợp lệ — đã huỷ để an toàn")
            return
        } catch {
            Self.log.error("Update staging failed: \(error.localizedDescription, privacy: .public)")
            showAlert("Cài đặt cập nhật thất bại", informativeText: error.localizedDescription)
            return
        }

        do {
            try launchHelperIfInstallable(extractedApp: extractedApp, release: info, expectedBundleIdentifier: expectedBundleIdentifier, workDir: workDir)
        } catch {
            Self.log.error("Update install failed: \(error.localizedDescription, privacy: .public)")
            showAlert("Cài đặt cập nhật thất bại", informativeText: error.localizedDescription)
            return
        }

        handedOverToInstallScript = true
        Self.log.info("Update verified and staged; quitting so the install helper can swap the bundle")
        AppModel.shared.quit()
    }

    /// Last gates (cheap, main-actor): the install folder must be writable,
    /// then the detached install script is launched. Throws before launching
    /// if anything is off, so the user never loses the running app for it.
    private func launchHelperIfInstallable(extractedApp: URL, release: ReleaseInfo, expectedBundleIdentifier: String, workDir: URL) throws {
        let currentBundleURL = Bundle.main.bundleURL
        guard currentBundleURL.pathExtension == "app" else {
            throw UpdaterError.currentBundleNotFound
        }

        // The script renames siblings next to the installed bundle, so that
        // folder must be writable. Checked BEFORE quitting: an app
        // translocated by Gatekeeper or sitting in a root-owned folder can't
        // be updated, and the user must not lose the running app for it.
        let installFolder = currentBundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: installFolder.path) else {
            throw UpdaterError.installFolderNotWritable(installFolder.path)
        }

        try launchInstallHelper(newAppPath: extractedApp.path, installedAppPath: currentBundleURL.path, expectedBundleIdentifier: expectedBundleIdentifier, expectedVersion: release.version, workDir: workDir)
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

/// Where the size-capped downloads landed. Plain Sendable values only.
private struct DownloadedUpdate: Sendable {
    let zipURL: URL
    let signatureBase64: String
}

/// All the slow, blocking update work. Nonisolated on purpose: it must never
/// run on the main actor (see THREADING in the file header), and it touches
/// no main-actor state — callers pass in everything it needs.
private enum UpdatePipeline {
    static func makeWorkDir() throws -> URL {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("KeystoneUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            throw UpdaterError.cannotWriteTempFile(error.localizedDescription)
        }
        return workDir
    }

    static func removeWorkDir(_ workDir: URL) {
        do {
            try FileManager.default.removeItem(at: workDir)
        } catch {
            updaterLog.error("Could not remove update work dir \(workDir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Download (size-capped)

    static func download(release: ReleaseInfo, into workDir: URL) async throws -> DownloadedUpdate {
        let zipURL = workDir.appendingPathComponent("Keystone.zip")
        let signatureURL = workDir.appendingPathComponent("Keystone.zip.sig")

        try await downloadCapped(from: release.zipURL, to: zipURL, timeout: 120, limit: UpdateLimits.maxZipBytes)
        try await downloadCapped(from: release.signatureURL, to: signatureURL, timeout: 30, limit: UpdateLimits.maxSignatureBytes)

        let signatureData: Data
        do {
            signatureData = try Data(contentsOf: signatureURL)
        } catch {
            throw UpdaterError.cannotWriteTempFile(error.localizedDescription)
        }
        guard let decoded = String(data: signatureData, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return DownloadedUpdate(zipURL: zipURL, signatureBase64: decoded.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Downloads to a file (not into memory) and aborts as soon as the
    /// running byte count — or the server's declared length — exceeds
    /// `limit`. The final on-disk size is re-checked in case the delegate
    /// never saw an oversized progress callback.
    private static func downloadCapped(from url: URL, to destination: URL, timeout: TimeInterval, limit: Int) async throws {
        let delegate = SizeCapDownloadDelegate(limit: limit)
        let request = URLRequest(url: url, timeoutInterval: timeout)

        let tempFile: URL
        let response: URLResponse
        do {
            (tempFile, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        } catch {
            // The delegate cancels the task when the cap is hit; report that
            // as "too large" rather than the generic "cancelled".
            if delegate.exceededLimit { throw UpdaterError.downloadTooLarge(limit) }
            throw error
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempFile)  // best-effort: the system temp file is ours to drop; the real failure is thrown below
            throw URLError(.badServerResponse)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: tempFile.path)
        let actualBytes = (attributes[.size] as? NSNumber)?.int64Value ?? Int64.max
        guard UpdateLimits.isAcceptable(byteCount: actualBytes, expectedContentLength: http.expectedContentLength, limit: limit) else {
            try? FileManager.default.removeItem(at: tempFile)  // best-effort, see above
            throw UpdaterError.downloadTooLarge(limit)
        }

        do {
            try FileManager.default.moveItem(at: tempFile, to: destination)
        } catch {
            throw UpdaterError.cannotWriteTempFile(error.localizedDescription)
        }
    }

    // MARK: Verify + stage

    /// Runs every gate between "bytes on disk" and "ready to launch the
    /// helper": Ed25519, extract, plist cross-check, codesign, quarantine.
    /// Returns the staged `Keystone.app`. Throws `UpdaterError.signatureInvalid`
    /// when the signature gate fails.
    static func verifyAndStage(
        download: DownloadedUpdate,
        release: ReleaseInfo,
        currentVersion: SemVer,
        expectedBundleIdentifier: String,
        publicKeyBase64: String
    ) async throws -> URL {
        let zipData: Data
        do {
            zipData = try Data(contentsOf: download.zipURL, options: .mappedIfSafe)
        } catch {
            throw UpdaterError.cannotWriteTempFile(error.localizedDescription)
        }

        // MANDATORY SECURITY GATE — non-bypassable. A downloaded update is
        // about to be unzipped-into-place and executed; it must never
        // install without a valid Ed25519 signature under the embedded
        // public key. Any failure here aborts and tells the user why.
        guard UpdateVerifier.isValid(
            zipData: zipData,
            signatureBase64: download.signatureBase64,
            publicKeyBase64: publicKeyBase64
        ) else {
            updaterLog.error("Update signature verification FAILED — install aborted")
            throw UpdaterError.signatureInvalid
        }

        let fm = FileManager.default
        let extractDir = download.zipURL.deletingLastPathComponent().appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", ["-x", "-k", download.zipURL.path, extractDir.path])

        guard let extractedApp = try findKeystoneApp(in: extractDir) else {
            throw UpdaterError.appNotFoundInDownload
        }

        // The signature only proves the zip was once genuinely signed; check
        // the bundle really is the build this release advertises (blocks a
        // replayed old signed zip served under a newer tag).
        let staged = try readStagedInfo(of: extractedApp)
        let check = UpdateCheck.validateStagedBundle(
            bundleIdentifier: staged.bundleIdentifier,
            shortVersion: staged.shortVersion,
            expectedBundleIdentifier: expectedBundleIdentifier,
            offeredVersion: release.version,
            currentVersion: currentVersion
        )
        guard check == .ok else {
            updaterLog.error("Staged bundle rejected: \(String(describing: check), privacy: .public)")
            throw UpdaterError.stagedBundleRejected(check.userMessage)
        }

        try runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", extractedApp.path])
        try runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", extractedApp.path])

        return extractedApp
    }

    /// Reads Info.plist directly (not `Bundle(url:)`, which caches).
    private static func readStagedInfo(of app: URL) throws -> (bundleIdentifier: String?, shortVersion: String?) {
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

    private static func findKeystoneApp(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents.first { $0.lastPathComponent == "Keystone.app" }
    }

    /// Blocks until the child exits — only ever call from off the main actor.
    @discardableResult
    private static func runProcess(_ executablePath: String, _ arguments: [String]) throws -> String {
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
        // Drain before waiting: a child that fills the pipe buffer would
        // otherwise block forever on write while we block on exit.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            updaterLog.error("\(executablePath, privacy: .public) exited \(process.terminationStatus): \(output, privacy: .public)")
            throw UpdaterError.processExitedNonZero(executablePath, process.terminationStatus, output)
        }
        return output
    }
}

/// Per-task delegate that cancels a download the moment it grows past the
/// cap, instead of letting a hostile server stream unbounded data to disk.
private final class SizeCapDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let limit: Int
    private let exceeded = OSAllocatedUnfairLock(initialState: false)

    init(limit: Int) {
        self.limit = limit
    }

    var exceededLimit: Bool { exceeded.withLock { $0 } }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Unknown length arrives as NSURLSessionTransferSizeUnknown (-1),
        // which `isAcceptable` treats as "no claim".
        guard !UpdateLimits.isAcceptable(byteCount: totalBytesWritten, expectedContentLength: totalBytesExpectedToWrite, limit: limit) else { return }
        exceeded.withLock { $0 = true }
        downloadTask.cancel()
    }

    // Required by the protocol. The async `download(for:delegate:)` call
    // hands the file back to the caller, so nothing to do here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

private enum UpdaterError: LocalizedError {
    case cannotWriteTempFile(String)
    case processLaunchFailed(String, String)
    case processExitedNonZero(String, Int32, String)
    case appNotFoundInDownload
    case currentBundleNotFound
    case stagedBundleRejected(String)
    case installFolderNotWritable(String)
    case signatureInvalid
    case downloadTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .signatureInvalid:
            return "Chữ ký bản cập nhật không hợp lệ — đã huỷ để an toàn"
        case .downloadTooLarge(let limit):
            let limitText = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            return "Tệp tải về lớn hơn giới hạn cho phép (\(limitText)) — đã huỷ, không cài gì cả"
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
