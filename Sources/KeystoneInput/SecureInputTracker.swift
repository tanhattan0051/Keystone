// SecureInputTracker.swift — pure state machine for macOS "Secure Input"
// (design spec §7). No Carbon/AppKit: the caller samples
// `IsSecureEventInputEnabled()` and the frontmost app's name, and this decides
// what changed.
//
// While any app holds Secure Input (a password field, or — confirmed on
// 2026-09-28 — a Chrome tab like workplace.vietnix.vn), macOS hides every
// keystroke from CGEventTaps system-wide. Keystone cannot see keys, so
// Vietnamese silently stops working in every app. This is a macOS security
// feature and Keystone must NOT try to bypass it; the tracker only lets the app
// SHOW the state, name the likely culprit, and stop learning from a blind
// session (see DECISIONS.md "Secure Input: phát hiện và báo").

public struct SecureInputTracker: Sendable, Equatable {
    public enum Change: Equatable, Sendable {
        /// Secure Input just turned on. `holder` is the app that was frontmost
        /// at that moment — a best guess, `nil` if the name was unavailable.
        case began(holder: String?)
        case ended
    }

    public private(set) var isActive: Bool = false

    /// The app that was frontmost when Secure Input began. Captured ONCE, at the
    /// OFF→ON transition, and deliberately never refreshed while it stays on:
    /// `kCGSSessionSecureInputPID` always reports the CURRENT frontmost app, not
    /// the real holder (verified twice), so re-reading it later would blame
    /// whichever app the user switched to (e.g. Discord) instead of Chrome. The
    /// transition is the only moment the frontmost app is a sound guess.
    public private(set) var holder: String?

    public init() {}

    /// Feeds one sample. Returns the transition it caused, or `nil` when the
    /// state is unchanged (the common case — this runs on a periodic poll).
    public mutating func update(isEnabled: Bool, frontmostAppName: String?) -> Change? {
        switch (isActive, isEnabled) {
        case (false, true):
            isActive = true
            holder = frontmostAppName
            return .began(holder: holder)
        case (true, false):
            isActive = false
            holder = nil
            return .ended
        default:
            return nil
        }
    }

    /// The one-line status shown in the menu while Secure Input is on. It says
    /// what to do (leave that field/tab), not how to bypass anything.
    public static func statusMessage(holder: String?) -> String {
        let subject = holder ?? "Một ứng dụng"
        return "\(subject) đang bật nhập bảo mật (ô mật khẩu) — thoát ô/tab đó để gõ tiếp tiếng Việt"
    }
}
