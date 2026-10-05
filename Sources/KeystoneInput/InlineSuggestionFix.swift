// InlineSuggestionFix.swift — pure per-app gate for the inline-autocomplete
// workaround (KeystrokeExecutor's `clearInlineSuggestion`), used by
// App/AppModel.swift. No AppKit here — see DECISIONS.md "Sửa lỗi gợi ý: xoá
// phần gợi ý tự điền trước khi xoá lùi".
import KeystoneEngine

public enum InlineSuggestionFix {
    /// Bundle id of Spotlight, compared case-insensitively like `TerminalApps`
    /// (LaunchServices treats bundle ids case-insensitively).
    private static let spotlightBundleID = "com.apple.spotlight"

    /// Whether the workaround may run while `bundleID` has keyboard focus.
    /// Off in terminals: they have no inline-selection autocomplete, so the
    /// extra character + Backspace would be pure risk there. Off in Spotlight
    /// because OpenKey explicitly disables its own workaround there. On
    /// everywhere else, including `nil`/unbundled processes.
    public static func allowed(bundleID: String?) -> Bool {
        if TerminalApps.isTerminal(bundleID: bundleID) { return false }
        if let bundleID, bundleID.lowercased() == spotlightBundleID { return false }
        return true
    }

    /// Whether this particular edit gets the placeholder. Skipped only for a
    /// PURE deletion by the user's Backspace (no text to retype): OpenKey never
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
