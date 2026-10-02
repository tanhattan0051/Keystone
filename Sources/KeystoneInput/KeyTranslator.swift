// KeyTranslator.swift — pure, testable mapping from a RawKey to a KeyDecision.
//
// No CoreGraphics, no engine, no I/O: this is the part of the input layer
// that unit tests can exercise directly, per design spec Part B.
//
// Virtual keycodes (US ANSI layout):
//   Backspace = 51, Return = 36, KeypadEnter = 76, Tab = 48, Escape = 53,
//   ForwardDelete = 117, Left = 123, Right = 124, Down = 125, Up = 126,
//   Home = 115, End = 119, PageUp = 116, PageDown = 121.
//
// Tab, Escape and ForwardDelete are `.commitPassthrough`: they finalize the
// word and leave what precedes the caret alone, so the sentence position
// survives them. The arrows, Home, End, PageUp and PageDown are
// `.commitCaretMove`: they land the caret somewhere the engine has never
// seen, so they also make it forget the sentence position.
public enum KeyTranslator {
    public static func decide(_ k: RawKey) -> KeyDecision {
        if k.command || k.control || k.option { return .resetPassthrough }
        switch k.keyCode {
        case 51: return .backspace
        case 36, 76: return .commitNewline
        case 48, 53, 117:
            return .commitPassthrough
        case 123, 124, 125, 126, 115, 119, 116, 121:
            return .commitCaretMove
        default: break
        }
        if k.chars.count == 1, let ch = k.chars.first, isPrintable(ch) {
            return .character(ch)
        }
        return .passthrough
    }

    private static func isPrintable(_ ch: Character) -> Bool {
        if ch == " " { return true }
        if ch.isNewline { return false }
        return ch.isLetter || ch.isNumber || ch.isPunctuation || ch.isSymbol
    }
}
