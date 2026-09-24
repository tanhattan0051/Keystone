// KeyFocusTracker.swift — reads which app is actually ACCEPTING KEYBOARD
// INPUT right now, via the Accessibility API, as a correction on top of
// NSWorkspace's plain "frontmost application" notion.
//
// Why this exists: a non-activating floating panel (iTerm2's F1 hotkey
// window with "Floats" on, an NSPanel with NSWindowStyleMaskNonactivatingPanel)
// can take key focus WITHOUT ever activating its owning app — no
// NSWorkspace.didActivateApplicationNotification fires, and
// NSWorkspace.shared.frontmostApplication keeps naming whatever app was
// frontmost before the panel appeared. Apple defines
// kAXFocusedApplicationAttribute as "the application element that is
// currently accepting keyboard input" — exactly the question AppModel needs
// answered to mask autoCapitalize while a terminal has focus. See
// DECISIONS.md "Không tự viết hoa trong Terminal" → "Floating panels follow
// keyboard focus, not activation" for the research behind this
// (Karabiner-Elements, Input Source Pro, Hammerspoon all read AX for the
// same reason; the CGEvent field eventTargetUnixProcessID is NOT usable at
// Keystone's session-level tap for this — it still names the background app
// there).
//
// Why the main thread: Apple DTS guidance is to make Accessibility calls on
// the main thread, and a read that happens to land on one of Keystone's OWN
// windows runs AppKit code on the calling thread — which must be main. The
// cost of that is bounded by the 0.25s messaging timeout set below, and the
// CGEventTap itself runs on its own dedicated thread (see
// EventTapController), so a slow or hung AX read here never blocks typing.

import AppKit
import ApplicationServices
import KeystoneInput
import os

@MainActor
final class KeyFocusTracker {
    private static let log = Logger(subsystem: "com.tanta.keystone", category: "KeyFocus")

    /// Called with the bundle id of the app currently accepting keyboard
    /// input (`nil` for an unbundled app) after every `refresh()` whose AX
    /// read succeeded — a failed read calls nothing (see `refresh()`).
    /// `@MainActor` because `refresh()` only ever calls it from the main
    /// actor (this class is `@MainActor`), so the caller can assign a plain
    /// main-actor closure with no `Task` hop.
    var onFocus: (@MainActor (String?) -> Void)?

    private let systemWide: AXUIElement = AXUIElementCreateSystemWide()
    private var throttle = RefreshThrottle(interval: 0.1)

    /// Set only once `AXUIElementSetMessagingTimeout` reports `.success`, so
    /// a failed attempt (e.g. Accessibility not yet granted at launch)
    /// retries on the very next `refresh()` instead of being applied once
    /// and forgotten.
    private var didSetMessagingTimeout = false

    /// Coarse status for the last AX read, tracked purely so `readFocusedApp()`
    /// can log ONLY on a change (never per keystroke — Tân's error-discipline
    /// rule: never swallow silently, but don't spam either). `.ok` is the
    /// starting assumption, so a FIRST failure still logs (it's a change from
    /// `.ok`), but a tracker that's succeeding every time never logs anything.
    private enum ReadStatus: Equatable {
        case ok
        case axError(AXError)
        case unexpectedElementType
        case appUnresolved
        case noBundleIdentifier
    }
    private var lastLoggedStatus: ReadStatus = .ok

    /// Called on every switch-key-monitor input event (see
    /// AppModel.installSwitchKeyMonitors) and once at bootstrap. Cheap to
    /// call on every keystroke — the throttle is what keeps the actual AX
    /// read rare; see RefreshThrottle's header for why a request must never
    /// be dropped.
    func requestRefresh() {
        let now = ProcessInfo.processInfo.systemUptime
        switch throttle.request(at: now) {
        case .runNow:
            refresh()
        case .runAfter(let delay):
            // Stay main-actor-correct under Swift 6 strict concurrency
            // rather than DispatchQueue.main.asyncAfter + assumeIsolated.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.refresh()
            }
        case .alreadyScheduled:
            break
        }
    }

    /// Applies `AXUIElementSetMessagingTimeout` lazily, on the first
    /// `refresh()`, rather than in `init()`: at `init()` time (app launch)
    /// Accessibility is very often not yet trusted, and the call would fail
    /// silently. Doing it here means the very first refresh after the user
    /// grants Accessibility is what actually applies it, and `didSetMessagingTimeout`
    /// staying false on failure means every later refresh keeps retrying
    /// until it sticks.
    private func applyMessagingTimeoutIfNeeded() {
        guard !didSetMessagingTimeout else { return }
        // Apple's default AX messaging timeout is ~6s if the focused app
        // hangs; 0.25s keeps a stuck app from blocking this read for long.
        // There's no per-call timeout parameter — this is process-global on
        // the system-wide element — which is fine here because Keystone's
        // only other AX API use is AXIsProcessTrusted/AXIsProcessTrustedWithOptions,
        // neither of which sends an AX request to another app (unaffected
        // by a messaging timeout).
        let status = AXUIElementSetMessagingTimeout(systemWide, 0.25)
        if status == .success {
            didSetMessagingTimeout = true
        } else {
            Self.log.error("AXUIElementSetMessagingTimeout failed (AXError \(status.rawValue, privacy: .public)) — will retry on the next refresh")
        }
    }

    /// `throttle.didRun(at:)` is stamped with the time AFTER `readFocusedApp()`
    /// returns, not before it runs — so a slow read (bounded by the
    /// messaging timeout above) can't eat its own cooldown and keep the main
    /// thread busy on back-to-back reads.
    private func refresh() {
        applyMessagingTimeoutIfNeeded()
        let read = readFocusedApp()
        throttle.didRun(at: ProcessInfo.processInfo.systemUptime)
        // A failed read is "no new information", NOT "the app behind the
        // panel": falling back to NSWorkspace here would let one transient
        // AX timeout on a busy iTerm2 panel flip AppModel's key-focus app to
        // the app underneath and reset the engine mid-word. The activation
        // path already keeps the NSWorkspace answer current on its own.
        if case .app(let bundleID) = read { onFocus?(bundleID) }
    }

    /// What one AX read could tell about the app accepting keyboard input.
    private enum FocusRead {
        /// The focused app's bundle id — `nil` for an unbundled app (e.g.
        /// `swift run Keystone`), which is a real answer, not a failure.
        case app(bundleID: String?)
        /// The read failed; keep whatever is already known.
        case unknown
    }

    /// Reads `kAXFocusedApplicationAttribute` off the system-wide element —
    /// Apple's own definition is "the application element that is currently
    /// accepting keyboard input", which is exactly what a non-activating
    /// floating panel changes without NSWorkspace ever noticing. Any failure
    /// (Electron/Chromium apps can return `kAXErrorNoValue` for this
    /// attribute; a hung app times out) is `.unknown`.
    private func readFocusedApp() -> FocusRead {
        var focused: CFTypeRef?
        let copyStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focused)
        guard copyStatus == .success, let focused else {
            logIfChanged(.axError(copyStatus))
            return .unknown
        }
        // CF opaque types don't all support a safe `as?` bridging check —
        // verify the concrete CF type ID before treating `focused` as an
        // AXUIElement.
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            logIfChanged(.unexpectedElementType)
            return .unknown
        }
        let element = focused as! AXUIElement
        var pid: pid_t = 0
        let pidStatus = AXUIElementGetPid(element, &pid)
        guard pidStatus == .success else {
            logIfChanged(.axError(pidStatus))
            return .unknown
        }
        guard let runningApp = NSRunningApplication(processIdentifier: pid) else {
            logIfChanged(.appUnresolved)
            return .unknown
        }
        // A resolved NSRunningApplication with no bundle identifier (an
        // unbundled process, e.g. `swift run Keystone`) is a normal,
        // expected case — not an error like the pid failing to resolve at
        // all — so it gets its own, quieter log level.
        guard let bundleID = runningApp.bundleIdentifier else {
            logIfChanged(.noBundleIdentifier)
            return .app(bundleID: nil)
        }
        logIfChanged(.ok)
        return .app(bundleID: bundleID)
    }

    private func logIfChanged(_ status: ReadStatus) {
        guard status != lastLoggedStatus else { return }
        lastLoggedStatus = status
        switch status {
        case .ok:
            Self.log.info("AX focused-application read recovered")
        case .axError(let error):
            Self.log.error("AX focused-application read failed (AXError \(error.rawValue, privacy: .public)) — keeping the last known focus")
        case .unexpectedElementType:
            Self.log.error("AX focused-application read returned an unexpected CF type — keeping the last known focus")
        case .appUnresolved:
            Self.log.error("AX focused-application pid did not resolve to a running app — keeping the last known focus")
        case .noBundleIdentifier:
            Self.log.debug("focused app has no bundle identifier")
        }
    }
}
