// InlineSuggestionFix.swift — pure per-app gate for the inline-autocomplete
// workaround (KeystrokeExecutor's `inlineSuggestionClearing`), used by
// App/AppModel.swift. No AppKit here — see DECISIONS.md "Sửa lỗi gợi ý: xoá
// phần gợi ý tự điền trước khi xoá lùi".
import KeystoneEngine

/// How `KeystrokeExecutor` gets rid of an inline suggestion before it deletes.
public enum InlineSuggestionClearing: Sendable, Equatable {
    /// Post only the Backspaces (terminals, or the fix is off).
    case none
    /// Type a placeholder, then N+1 Backspaces (Chrome omnibox, Excel...).
    case placeholder
    /// One Forward Delete, then N Backspaces (Spotlight's completion pill).
    case forwardDelete
}

public enum InlineSuggestionFix {
    /// Bundle ids that get Forward Delete, compared case-insensitively like
    /// `TerminalApps` (LaunchServices treats bundle ids case-insensitively).
    /// `com.apple.campo` is Siri AI.app, which another IME's log shows as the
    /// macOS 27 Spotlight field's host ([VERIFY] on device, DECISIONS.md
    /// "Spotlight: Forward Delete để bỏ gợi ý").
    private static let forwardDeleteBundleIDs: Set<String> = ["com.apple.spotlight", "com.apple.campo"]

    /// Which workaround applies while `bundleID` has keyboard focus.
    /// `.none` in terminals: they have no inline-selection autocomplete, so
    /// the extra character + Backspace would be pure risk there.
    /// `.forwardDelete` in Spotlight, where a Backspace only removes the grey
    /// pill and the placeholder is untested. `.placeholder` everywhere else,
    /// including `nil`/unbundled processes.
    public static func clearing(bundleID: String?) -> InlineSuggestionClearing {
        if TerminalApps.isTerminal(bundleID: bundleID) { return .none }
        if let bundleID, forwardDeleteBundleIDs.contains(bundleID.lowercased()) { return .forwardDelete }
        return .placeholder
    }

    /// The mode to use when the focus read failed and only the frontmost app
    /// is known. Never `.forwardDelete`: a non-activating panel can hold key
    /// focus while another app is frontmost, and a Forward Delete sent there
    /// deletes the character after the caret. Sending nothing extra is the
    /// safe choice for a Spotlight host, whose placeholder path is untested.
    public static func clearingWhenFocusUnknown(frontmostBundleID: String?) -> InlineSuggestionClearing {
        let clearing = clearing(bundleID: frontmostBundleID)
        return clearing == .forwardDelete ? .none : clearing
    }

    /// The clearing to use for this particular edit: `configured` unless the
    /// edit is a pure Backspace deletion (see `appliesToEdit`).
    public static func clearing(
        configured: InlineSuggestionClearing, decision: KeyDecision, edit: EngineResult
    ) -> InlineSuggestionClearing {
        appliesToEdit(enabledForApp: configured != .none, decision: decision, edit: edit) ? configured : .none
    }

    /// Whether this particular edit gets the placeholder or Forward Delete.
    /// Skipped only for a PURE deletion by the user's Backspace (no text to
    /// retype): OpenKey never
    /// sends its empty character on Delete, and Delete over a selected
    /// suggestion should do what native Delete does (dismiss only the
    /// suggestion, keep what was typed). A Backspace that makes the engine
    /// re-render (e.g. "vieetj"+Backspace -> bs=2, "êt") is a normal rewrite:
    /// without the placeholder its first synthetic Backspace would eat only the
    /// selection and garble the word.
    public static func appliesToEdit(enabledForApp: Bool, decision: KeyDecision, edit: EngineResult) -> Bool {
        enabledForApp && !(decision == .backspace && edit.text.isEmpty)
    }

    /// Whether the AX focus read is worth running for this toggle: only while
    /// the engine can emit edits at all (Vietnamese on, or the English-mode
    /// macro path active — mirrors `TerminalApps.capitalizationCanFire` and
    /// the inactive path of `EngineController.handle`). Otherwise the
    /// workaround can never fire and the read would be wasted AX traffic.
    public static func needsFocusTracking(
        autoFixSuggestion: Bool,
        vietnameseEnabled: Bool,
        macrosEnabled: Bool,
        macrosExpandWhenVietnameseOff: Bool
    ) -> Bool {
        autoFixSuggestion && (vietnameseEnabled || (macrosEnabled && macrosExpandWhenVietnameseOff))
    }
}
