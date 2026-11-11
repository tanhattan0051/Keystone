// Contracts.swift — public value types shared across the input layer
// (design spec Part B).

/// One physical keystroke as observed by the event tap, translated into a
/// platform-neutral shape that `KeyTranslator` and `EngineController` can
/// consume without touching CoreGraphics directly (keeps them unit-testable).
public struct RawKey: Equatable, Sendable {
    public var keyCode: Int
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var chars: String

    public init(
        keyCode: Int,
        command: Bool = false,
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        chars: String
    ) {
        self.keyCode = keyCode
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
        self.chars = chars
    }
}

/// What `KeyTranslator` decided a `RawKey` means for the engine.
public enum KeyDecision: Equatable, Sendable {
    case character(Character)
    /// The kVK_Delete key: ask the engine to remove one raw keystroke.
    case backspace
    /// A commit key that leaves what precedes the caret alone (Tab, Escape,
    /// ForwardDelete): finalize the current word but let the original event
    /// pass through untouched.
    case commitPassthrough
    /// An arrow / Home / End / PageUp / PageDown key: finalize like
    /// `.commitPassthrough`, pass the key through, AND forget the sentence
    /// position — the caret lands where the engine cannot know what precedes it.
    case commitCaretMove
    /// Return / KeypadEnter: finalize the current word, let the key pass
    /// through, AND start a new sentence (for autoCapitalize).
    case commitNewline
    /// A Cmd/Ctrl/Option-chorded key. The chord may move the caret, paste,
    /// undo or switch apps, so the engine finalizes the in-progress word
    /// exactly like a caret move (commit + forget sentence position) and the
    /// chord passes through.
    case commitChord
    /// Any other key (function keys, keys with no printable char): passes
    /// through. While Vietnamese is on, the controller finalizes the word
    /// like a caret move first, since such keys can move focus. In English
    /// mode it drops the macro buffer, like a chord.
    case passthrough
}

/// The output side of the input layer: something that can realize an
/// `EngineResult` on screen. Implemented by the live CGEventTap sink in
/// production and by a recording fake in tests.
public protocol EventSink {
    func postBackspace(count: Int)
    /// One Forward Delete (fn+Delete, virtual key 117).
    func postForwardDelete()
    func postText(_ text: String)
}

/// App-compatibility knobs for how the tap posts synthesized keystrokes
/// (design spec E.2/E.3). Pushed from `AppModel` into `EventTapController`
/// as a snapshot, read once per edit under a small lock — see
/// `EventTapController.updateBehavior`.
public struct InputBehavior: Sendable, Equatable {
    /// "Gửi từng phím" — post the composed text one grapheme at a time
    /// instead of a single `postText(wholeString)` call.
    public var sendEachKeystroke: Bool
    /// "Sửa lỗi gợi ý" — post the composed Unicode string on the synthetic
    /// keyDown only, not on keyUp too (the documented anti-double-char fix
    /// for browsers/Excel). Default false = both events carry the string,
    /// the tap's original behavior; this is an opt-in remedy.
    public var textOnKeyDownOnly: Bool
    /// "Sửa lỗi gợi ý" — how to clear an inline suggestion before the
    /// backspaces (see `KeystrokeExecutor.execute`). Needed because an
    /// inline-autocomplete selection (Chrome omnibox, Excel) or Spotlight's
    /// completion pill eats the first synthetic Backspace, leaving the old
    /// character behind ("hộ" -> "hoộ", "ww" -> "ưw"). `.placeholder` mirrors
    /// OpenKey's workaround, `.forwardDelete` is for Spotlight. Already chosen
    /// per app by the caller (`.none` in terminals); default `.none`.
    public var inlineSuggestionClearing: InlineSuggestionClearing

    public init(
        sendEachKeystroke: Bool = false,
        textOnKeyDownOnly: Bool = false,
        inlineSuggestionClearing: InlineSuggestionClearing = .none
    ) {
        self.sendEachKeystroke = sendEachKeystroke
        self.textOnKeyDownOnly = textOnKeyDownOnly
        self.inlineSuggestionClearing = inlineSuggestionClearing
    }
}
