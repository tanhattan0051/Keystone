// RealisticTyping.swift — shared "what's actually on screen" test harness for
// suites that drive EngineController.handle and must model reality, not just
// replay edits.
//
// The real tap (EventTapController.handle) does two things per keystroke, in
// order: (1) inject the edit EngineController returns, synchronously, then
// (2) let the ORIGINAL physical key continue on to the app, but only when
// `suppress` is false. A harness that only ever applies step (1) is blind to
// step (2) — it cannot see a physical key EngineController failed to
// suppress land on screen, which is exactly the screen-desync bug fixed here
// (see DECISIONS.md "Suppress every character the engine took ownership of,
// even a no-op one"). `applyRealistically` below models both steps;
// `typeAndFlush` is the common "type a word, then Return" shape every
// EngineController-driven suite in this file needs.
//
// Shared by EngineControllerTests.swift, LexiconRestoreTests.swift and
// LexiconRealDictionaryTests.swift, which each used to carry their own
// edit-only copy of this loop.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

func letter(_ c: Character) -> RawKey { RawKey(keyCode: 0, chars: String(c)) }
let RETURN = RawKey(keyCode: 36, chars: "\r")
let BACKSPACE = RawKey(keyCode: 51, chars: "")

/// Applies one `EngineController.handle` result to the simulated on-screen
/// buffer `acc`, in the same order as the real tap: the edit first, then the
/// physical key itself if it was left unsuppressed.
///
/// `.character`'s physical passthrough appends the typed letter; `.backspace`'s
/// removes one character (an ordinary, unsuppressed Delete key). The other
/// decisions (`.commitPassthrough`/`.commitNewline`/`.commitChord`/
/// `.passthrough`) carry no text worth modeling on this simulated screen —
/// Return's physical key is "\r", which these tests compare against
/// plain committed words with no newline, so it is deliberately not appended.
func applyRealistically(
    _ handled: (suppress: Bool, edit: EngineResult?, decision: KeyDecision),
    to acc: inout [Unicode.Scalar]
) {
    if let edit = handled.edit {
        if edit.backspaceCount > 0 { acc.removeLast(min(edit.backspaceCount, acc.count)) }
        acc.append(contentsOf: edit.text.unicodeScalars)
    }
    guard !handled.suppress else { return }
    switch handled.decision {
    case .character(let ch):
        acc.append(contentsOf: String(ch).unicodeScalars)
    case .backspace:
        if !acc.isEmpty { acc.removeLast() }
    default:
        break
    }
}

/// Feeds `telex` through a fresh `EngineController`, then a trailing Return,
/// reconstructing the on-screen text exactly as `EventTapController` would
/// apply it (see `applyRealistically`). `lexicon` is installed before typing
/// starts, mirroring `EngineController.setLexicon` being called once up
/// front (matches every existing call site's usage).
func typeAndFlush(_ telex: String, config: EngineConfig = EngineConfig(), lexicon: Lexicon? = nil) -> String {
    let c = EngineController(config: config)
    c.setLexicon(lexicon)
    var acc: [Unicode.Scalar] = []
    for ch in telex {
        applyRealistically(c.handle(letter(ch)), to: &acc)
    }
    applyRealistically(c.handle(RETURN), to: &acc)
    return String(String.UnicodeScalarView(acc))
}
