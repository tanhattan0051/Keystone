// Contracts.swift — public value types and small thread-safe caches shared
// across the input layer (design spec Part B).
//
// Everything here is either a plain value type or a tiny lock-protected cache
// meant to be read on the CGEventTap hot path. See §3 of the design spec:
// the tap callback may only touch the engine and a small in-memory cache —
// no system calls, no allocation-heavy work per keystroke.

import os

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
    /// A modifier-chorded key: drop the in-progress word and pass through.
    case resetPassthrough
    /// Anything else: pass through, engine untouched.
    case passthrough
}

/// The output side of the input layer: something that can realize an
/// `EngineResult` on screen. Implemented by the live CGEventTap sink in
/// production and by a recording fake in tests.
public protocol EventSink {
    func postBackspace(count: Int)
    func postText(_ text: String)
}

/// Small snapshot of system state the tap callback is allowed to read.
/// Populated off the hot path (NSWorkspace notifications, low-frequency
/// timers) and read under a tiny lock — see design spec Part B §3.
public struct SystemState: Sendable, Equatable {
    public var frontAppBundleID: String?
    public var secureInputActive: Bool

    public init(frontAppBundleID: String? = nil, secureInputActive: Bool = false) {
        self.frontAppBundleID = frontAppBundleID
        self.secureInputActive = secureInputActive
    }
}

/// Thread-safe cache for `SystemState`. Reads/writes are guarded by an
/// `OSAllocatedUnfairLock`, cheap enough to call from the tap callback.
public final class SystemStateCache: @unchecked Sendable {
    private var state = SystemState()
    private let lock = OSAllocatedUnfairLock()

    public init() {}

    public func snapshot() -> SystemState {
        lock.withLock { state }
    }

    public func mutate(_ f: (inout SystemState) -> Void) {
        // withLockUnchecked: the caller's closure isn't Sendable, but mutation is
        // fully serialized by the lock (the class is @unchecked Sendable).
        lock.withLockUnchecked { f(&state) }
    }
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
    /// "Sửa lỗi gợi ý" — before the backspaces, type a placeholder character
    /// and send one extra Backspace (see `KeystrokeExecutor.execute`). Needed
    /// because an inline-autocomplete selection (Chrome omnibox, Excel) eats
    /// the first synthetic Backspace, leaving the old character behind
    /// ("hộ" -> "hoộ"). Mirrors OpenKey's workaround. Already masked per app
    /// by the caller (off in terminals/Spotlight); default false.
    public var clearsInlineSuggestion: Bool

    public init(
        sendEachKeystroke: Bool = false,
        textOnKeyDownOnly: Bool = false,
        clearsInlineSuggestion: Bool = false
    ) {
        self.sendEachKeystroke = sendEachKeystroke
        self.textOnKeyDownOnly = textOnKeyDownOnly
        self.clearsInlineSuggestion = clearsInlineSuggestion
    }
}
