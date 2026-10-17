// FocusResetPolicy.swift — pure decision: should an AX-reported key-focus
// change throw away the engine's composing buffer?
//
// The AX re-check (App/KeyFocusTracker.swift) is triggered by the global
// NSEvent monitor seeing the FIRST keystroke into a new target — e.g. right
// after F1 hides iTerm2's floating hotkey panel. The CGEventTap runs on its
// own thread and has ALREADY fed that keystroke (maybe more) to the engine by
// the time the refresh lands. An unconditional reset would erase them: typing
// "ddi" (Telex "đi") became "d" + "di". So we reset only if the current word
// began BEFORE the event that triggered the refresh.
//
// Safety argument. `WordStartTracker` is fed every real key the monitors see,
// so its word-start estimate can only be EARLIER than (or equal to) the
// engine's real word start: Keystone's own synthetic events always follow the
// real key that began the word, and keys the estimate counts as word keys but
// the engine does not (digits under Telex, "[" "]" under VNI) merely move the
// estimate earlier. An earlier estimate makes `shouldResetOnFocusChange` MORE
// likely to reset, never less, so the policy skips a reset only when the real
// word also began at/after the trigger. Residual risk, accepted: a word begun
// in the OLD target within one refresh window (RefreshThrottle, 0.1 s) right
// before focus moved survives into the new target's buffer.
//
// Timestamps are plain seconds on one monotonic clock (NSEvent.timestamp and
// ProcessInfo.systemUptime share it); nothing here touches AppKit.

import Foundation   // TimeInterval only

/// What a monitored input event means for "is a word being composed?".
public enum MonitoredKeyKind: Sendable, Equatable {
    /// A key that starts/continues a word (letter, digit, "[" or "]").
    case wordKey
    /// Ends any word in progress (space, punctuation, Return, arrows, chords,
    /// mouse-down).
    case boundary
    /// Neither (Backspace, function keys, unknown) — leaves the estimate alone.
    case neutral
}

public enum FocusResetPolicy {
    /// Classifies a keyDown. `characters` is the typed text
    /// (NSEvent.characters); ⌘/⌃/⌥ chords are boundaries before the text is
    /// even looked at. Mouse-downs are boundaries too — callers
    /// record `.boundary` for them directly.
    public static func classify(keyCode: UInt16, characters: String, modifiers: ModifierSet) -> MonitoredKeyKind {
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            return .boundary
        }
        switch keyCode {
        case 51:
            return .neutral
        // Same keycodes as KeyTranslator: Return, KeypadEnter, Tab, Escape,
        // ForwardDelete, arrows, Home, End, PageUp, PageDown.
        case 36, 76, 48, 53, 117, 123, 124, 125, 126, 115, 119, 116, 121:
            return .boundary
        default:
            break
        }
        guard characters.count == 1, let ch = characters.first else { return .neutral }
        if ch == "[" || ch == "]" { return .wordKey }
        if ch.isLetter || ch.isNumber { return .wordKey }
        if ch == " " || ch.isPunctuation || ch.isSymbol { return .boundary }
        return .neutral   // control/private-use characters (F-keys), newlines
    }

    /// `triggerTime == nil` (bootstrap / no event) → reset. `currentWordStart
    /// == nil` → nothing composing by our estimate; resetting an empty buffer
    /// is harmless. A word that began at/after the trigger was typed into the
    /// NEW target, so keep it.
    public static func shouldResetOnFocusChange(currentWordStart: TimeInterval?, triggerTime: TimeInterval?) -> Bool {
        guard let triggerTime else { return true }
        guard let currentWordStart else { return true }
        return currentWordStart < triggerTime
    }
}

/// Estimates when the word the engine is composing began, from the stream of
/// monitored events.
public struct WordStartTracker: Sendable {
    public private(set) var currentWordStart: TimeInterval?

    public init() {}

    public mutating func record(_ kind: MonitoredKeyKind, at time: TimeInterval) {
        switch kind {
        case .wordKey:
            if currentWordStart == nil { currentWordStart = time }
        case .boundary:
            currentWordStart = nil
        case .neutral:
            break
        }
    }

    /// The engine buffer was reset, so no word is in progress.
    public mutating func reset() {
        currentWordStart = nil
    }
}
