// UpdateInstallScriptTests.swift — pins the relaunch/swap script the updater
// runs after Keystone quits. The pure string tests check quoting and syntax;
// the integration tests RUN the generated script with /bin/bash against fake
// ad-hoc-signed bundles in a unique temp dir, so the failure paths (the ones
// that used to delete the user's only IME) are exercised for real.

import Testing
import Foundation
@testable import KeystoneInput

@Suite("UpdateInstallScript (pure)")
struct UpdateInstallScriptPureTests {
    private func sample(installed: String = "/Applications/Keystone.app") -> String {
        UpdateInstallScript.make(
            waitForPID: 123,
            stagedAppPath: "/tmp/work dir/extracted/Keystone.app",
            installedAppPath: installed,
            workDirPath: "/tmp/work dir",
            expectedBundleIdentifier: "com.tanta.keystone",
            expectedVersion: "1.2.0",
            logFilePath: "/tmp/log dir/update.log"
        )
    }

    @Test func shellQuotedWrapsSpaces() {
        #expect(UpdateInstallScript.shellQuoted("/a b/c") == "'/a b/c'")
    }

    @Test func shellQuotedEscapesSingleQuotes() {
        #expect(UpdateInstallScript.shellQuoted("it's") == "'it'\\''s'")
    }

    @Test func shellQuotedNeutralisesShellMetacharacters() {
        #expect(UpdateInstallScript.shellQuoted("$(rm -rf /); `x`") == "'$(rm -rf /); `x`'")
    }

    @Test func generatedScriptPassesBashSyntaxCheck() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ks-syntax-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try sample(installed: "/Applications/Kei's App/Keystone.app").write(to: tmp, atomically: true, encoding: .utf8)
        let result = try ScriptRunner.run("/bin/bash", ["-n", tmp.path])
        #expect(result.status == 0, "bash -n: \(result.output)")
    }

    @Test func scriptNeverRemovesTheInstalledPathDirectly() {
        let script = sample()
        #expect(!script.contains("rm -rf '/Applications/Keystone.app'"))
        #expect(!script.contains("rm -rf \"$INSTALLED\""))
    }

    @Test func scriptHasSafetyHeader() {
        let script = sample()
        #expect(script.hasPrefix("#!/bin/bash\n"))
        #expect(script.contains("set -euo pipefail"))
        #expect(script.contains("trap "))
    }
}

/// Small helper shared by the integration tests below.
enum ScriptRunner {
    struct Result { let status: Int32; let output: String }

    static func run(_ exe: String, _ args: [String]) throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        // Read before waiting so a chatty child can't fill the pipe and hang.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }
}

@Suite("UpdateInstallScript (integration)", .serialized)
struct UpdateInstallScriptIntegrationTests {
    private let bundleID = "com.tanta.keystone.test"
    private let fm = FileManager.default

    /// Everything one scenario needs, rooted in a unique temp dir.
    private struct Sandbox {
        let root: URL
        var installedDir: URL { root.appendingPathComponent("Applications", isDirectory: true) }
        var installedApp: URL { installedDir.appendingPathComponent("Keystone.app") }
        var workDir: URL { root.appendingPathComponent("work", isDirectory: true) }
        var stagedApp: URL { workDir.appendingPathComponent("extracted/Keystone.app") }
        var logFile: URL { root.appendingPathComponent("logs/update.log") }
        var marker: URL { root.appendingPathComponent("relaunch-marker.txt") }
        var relaunchHelper: URL { root.appendingPathComponent("relaunch.sh") }
        var scriptFile: URL { workDir.appendingPathComponent("install.sh") }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = fm.temporaryDirectory.appendingPathComponent("ks-update-\(UUID().uuidString)", isDirectory: true)
        let box = Sandbox(root: root)
        try fm.createDirectory(at: box.installedDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: box.workDir.appendingPathComponent("extracted"), withIntermediateDirectories: true)
        let helper = "#!/bin/bash\necho \"$1\" >> '\(box.marker.path)'\n"
        try helper.write(to: box.relaunchHelper, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.relaunchHelper.path)
        return box
    }

    /// Builds a minimal, ad-hoc-signed app bundle at `url`.
    private func makeApp(at url: URL, bundleID: String, version: String) throws {
        let macOS = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": "Keystone",
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        let exe = macOS.appendingPathComponent("Keystone")
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let sign = try ScriptRunner.run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
        #expect(sign.status == 0, "codesign: \(sign.output)")
    }

    private func installedVersion(_ box: Sandbox) throws -> String? {
        let data = try Data(contentsOf: box.installedApp.appendingPathComponent("Contents/Info.plist"))
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return obj?["CFBundleShortVersionString"] as? String
    }

    private func relaunchMarker(_ box: Sandbox) -> [String] {
        guard let text = try? String(contentsOf: box.marker, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private func leftoverSiblings(_ box: Sandbox) throws -> [String] {
        try fm.contentsOfDirectory(atPath: box.installedDir.path).filter { $0.hasPrefix(".Keystone-update-") }
    }

    private func runScript(_ box: Sandbox, pid: Int32, expectedVersion: String = "2.0.0",
                           waitTimeout: Int = 5) throws -> ScriptRunner.Result {
        let script = UpdateInstallScript.make(
            waitForPID: pid,
            stagedAppPath: box.stagedApp.path,
            installedAppPath: box.installedApp.path,
            workDirPath: box.workDir.path,
            expectedBundleIdentifier: bundleID,
            expectedVersion: expectedVersion,
            logFilePath: box.logFile.path,
            relaunchCommand: box.relaunchHelper.path,
            waitTimeoutSeconds: waitTimeout
        )
        // The real updater writes the script inside the work dir too, which
        // is why the script's cleanup can delete itself.
        try script.write(to: box.scriptFile, atomically: true, encoding: .utf8)
        return try ScriptRunner.run("/bin/bash", [box.scriptFile.path])
    }

    private func exitedPID() throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try p.run()
        p.waitUntilExit()
        return p.processIdentifier
    }

    private var codesignAvailable: Bool { fm.isExecutableFile(atPath: "/usr/bin/codesign") }

    // Records one issue instead of silently passing when codesign is absent.
    private func requireCodesign() -> Bool {
        if !codesignAvailable { Issue.record("SKIPPED: /usr/bin/codesign missing, integration test not run") }
        return codesignAvailable
    }

    private func cleanUp(_ box: Sandbox) { try? fm.removeItem(at: box.root) }

    @Test func happyPathSwapsInNewVersionAndCleansUp() throws {
        guard requireCodesign() else { return }
        let box = try makeSandbox()
        defer { cleanUp(box) }
        try makeApp(at: box.installedApp, bundleID: bundleID, version: "1.0.0")
        try makeApp(at: box.stagedApp, bundleID: bundleID, version: "2.0.0")

        let result = try runScript(box, pid: try exitedPID())

        #expect(result.status == 0, "\(result.output)")
        #expect(try installedVersion(box) == "2.0.0")
        #expect(try leftoverSiblings(box).isEmpty)
        #expect(!fm.fileExists(atPath: box.workDir.path))
        #expect(relaunchMarker(box) == [box.installedApp.path])
        #expect(fm.fileExists(atPath: box.logFile.path))
    }

    @Test func wrongVersionLeavesInstalledUntouchedAndRelaunchesOld() throws {
        guard requireCodesign() else { return }
        let box = try makeSandbox()
        defer { cleanUp(box) }
        try makeApp(at: box.installedApp, bundleID: bundleID, version: "1.0.0")
        try makeApp(at: box.stagedApp, bundleID: bundleID, version: "1.5.0")

        let result = try runScript(box, pid: try exitedPID())

        #expect(result.status != 0)
        #expect(try installedVersion(box) == "1.0.0")
        #expect(try leftoverSiblings(box).isEmpty)
        #expect(!fm.fileExists(atPath: box.workDir.path))
        #expect(relaunchMarker(box) == [box.installedApp.path])
    }

    @Test func wrongBundleIdentifierLeavesInstalledUntouched() throws {
        guard requireCodesign() else { return }
        let box = try makeSandbox()
        defer { cleanUp(box) }
        try makeApp(at: box.installedApp, bundleID: bundleID, version: "1.0.0")
        try makeApp(at: box.stagedApp, bundleID: "com.evil.app", version: "2.0.0")

        let result = try runScript(box, pid: try exitedPID())

        #expect(result.status != 0)
        #expect(try installedVersion(box) == "1.0.0")
        #expect(try leftoverSiblings(box).isEmpty)
        #expect(!fm.fileExists(atPath: box.workDir.path))
        #expect(relaunchMarker(box) == [box.installedApp.path])
    }

    @Test func missingStagedAppLeavesInstalledUntouched() throws {
        guard requireCodesign() else { return }
        let box = try makeSandbox()
        defer { cleanUp(box) }
        try makeApp(at: box.installedApp, bundleID: bundleID, version: "1.0.0")
        // staged app intentionally never created: ditto must fail.

        let result = try runScript(box, pid: try exitedPID())

        #expect(result.status != 0)
        #expect(try installedVersion(box) == "1.0.0")
        #expect(try leftoverSiblings(box).isEmpty)
        #expect(relaunchMarker(box) == [box.installedApp.path])
    }

    @Test func tamperedStagedBundleFailsCodesignAndLeavesInstalledUntouched() throws {
        guard requireCodesign() else { return }
        let box = try makeSandbox()
        defer { cleanUp(box) }
        try makeApp(at: box.installedApp, bundleID: bundleID, version: "1.0.0")
        try makeApp(at: box.stagedApp, bundleID: bundleID, version: "2.0.0")
        // Modify a sealed file after signing (id and version stay correct, so
        // only the codesign check can catch it): the seal no longer matches.
        let plistURL = box.stagedApp.appendingPathComponent("Contents/Info.plist")
        var plist = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any]
        )
        plist["TamperedAfterSigning"] = true
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)

        let result = try runScript(box, pid: try exitedPID())

        #expect(result.status != 0)
        #expect(try installedVersion(box) == "1.0.0")
        #expect(try leftoverSiblings(box).isEmpty)
        #expect(relaunchMarker(box) == [box.installedApp.path])
    }

    @Test func waitTimeoutDoesNotSwapOrRelaunch() throws {
        guard requireCodesign() else { return }
        let box = try makeSandbox()
        defer { cleanUp(box) }
        try makeApp(at: box.installedApp, bundleID: bundleID, version: "1.0.0")
        try makeApp(at: box.stagedApp, bundleID: bundleID, version: "2.0.0")

        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        defer {
            sleeper.terminate()
            sleeper.waitUntilExit()
        }

        let result = try runScript(box, pid: sleeper.processIdentifier, waitTimeout: 1)

        #expect(result.status != 0)
        #expect(try installedVersion(box) == "1.0.0")
        #expect(try leftoverSiblings(box).isEmpty)
        #expect(relaunchMarker(box).isEmpty, "app is still running; must not relaunch")
        #expect(!fm.fileExists(atPath: box.workDir.path))
    }
}
