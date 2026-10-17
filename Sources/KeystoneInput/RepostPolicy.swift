// RepostPolicy.swift — pure rule for when the tap may let the user's own key
// event through (re-posted, tagged) instead of synthesizing a text event.
//
// A synthetic text event is built from scratch as virtual key 0, so the app
// sees the wrong keycode (web `e.code` is "KeyA" for every letter), loses
// modifier flags (Shift+Space) and autorepeat, and a hold-style key such as
// Space in Figma sees keyUp without a matching keyDown. When the engine's edit
// is nothing but the character the user just typed, none of that synthesis is
// needed: re-emitting the original event keeps all of it.
import KeystoneEngine

public enum RepostPolicy {
    /// True when the edit is a bare append of exactly the typed character: no
    /// Backspace, and `edit.text` is that one character. Anything else
    /// (a tone rewrite, a macro, auto-capitalization, a commit that rewrites
    /// the word) must go through the synthetic path.
    ///
    /// "Sửa lỗi gợi ý" needs no special case: its placeholder is only sent when
    /// `backspaceCount > 0` (see `KeystrokeExecutor.execute`), a plain insertion
    /// already replaces a selected inline suggestion, and `textOnKeyDownOnly` /
    /// `sendEachKeystroke` only shape synthesized events, of which there are none.
    public static func canRepostOriginal(decision: KeyDecision, edit: EngineResult) -> Bool {
        guard case .character(let ch) = decision else { return false }
        return edit.backspaceCount == 0 && edit.text == String(ch)
    }
}
