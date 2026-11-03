// MenuBarState.swift — pure decision of what the menu bar icon says about the
// input method. No AppKit/SwiftUI: App/ passes in the flags it already tracks
// and renders the result.
//
// Why it exists: the icon used to show "V" whenever `enabled` was true, even
// when the event tap could not run (no Accessibility permission, or a relaunch
// still needed). The indicator lied exactly when typing was broken. Now it
// shows a warning triangle in those states, and a VoiceOver label in all of them.

public enum MenuBarState: Equatable, Sendable {
    case vietnamese
    case english
    case secureInput
    case permissionMissing
    case needsRelaunch

    public enum Glyph: Equatable, Sendable {
        case letter(String)
        case systemImage(String)
    }

    /// Priority: no permission, then Secure Input, then needs-relaunch, then V/E.
    ///
    /// Secure Input is checked BEFORE needsRelaunch on purpose: DECISIONS.md
    /// records that it is unverified whether the tap reports "running" under
    /// Secure Input, and `AppModel.refresh()` has no guard for it. A blind tap
    /// could therefore flip `needsRelaunch` and wrongly tell someone typing a
    /// password to relaunch. The menu in MenuBarContent.swift already checks in
    /// this same order.
    ///
    /// There is deliberately no `tapRunning` input: `AppModel.refresh()` raises
    /// `needsRelaunch` only after two polls of a non-running tap, and that grace
    /// period is what keeps the glyph from flashing a warning at launch.
    public init(accessibilityTrusted: Bool, needsRelaunch: Bool, secureInputActive: Bool, enabled: Bool) {
        if !accessibilityTrusted {
            self = .permissionMissing
        } else if secureInputActive {
            self = .secureInput
        } else if needsRelaunch {
            self = .needsRelaunch
        } else {
            self = enabled ? .vietnamese : .english
        }
    }

    public var glyph: Glyph {
        switch self {
        case .vietnamese: return .letter("V")
        case .english: return .letter("E")
        case .secureInput: return .systemImage("lock.fill")
        case .permissionMissing, .needsRelaunch: return .systemImage("exclamationmark.triangle.fill")
        }
    }

    /// True when Keystone itself cannot type. Secure Input is excluded: it is
    /// temporary and held by another app.
    public var isInputStopped: Bool {
        switch self {
        case .permissionMissing, .needsRelaunch: return true
        case .vietnamese, .english, .secureInput: return false
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .vietnamese: return "Keystone: đang gõ tiếng Việt"
        case .english: return "Keystone: đang gõ tiếng Anh"
        case .secureInput: return "Keystone: nhập bảo mật đang bật, tạm không gõ được tiếng Việt"
        case .permissionMissing: return "Keystone: chưa có quyền Accessibility, bộ gõ không chạy"
        case .needsRelaunch: return "Keystone: cần khởi động lại để bộ gõ chạy"
        }
    }
}
