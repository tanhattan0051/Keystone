// AutoCapitalizeForgetsAfterEditTests.swift — the engine cannot see what a
// passthrough Backspace deleted or where an arrow key moved the caret, so it
// must stop trusting its sentence position after either one: it falls back to
// `.afterReset` (no auto-capital by itself; a freshly typed terminator plus
// whitespace still confirms). See DECISIONS.md "Auto-capitalize: quên vị trí
// câu sau Backspace / phím di chuyển con trỏ".

import Testing
@testable import KeystoneEngine

/// A simulated screen that models what the real app does with a Backspace:
/// `EngineController` suppresses a Backspace only while the engine owns a
/// composing word; otherwise the physical Delete key passes through and
/// removes one on-screen character the engine never sees. `Screen.backspace`
/// mirrors that split via `engine.isComposing`.
private final class Screen {
    let engine: Engine
    private var scalars: [Unicode.Scalar] = []

    var text: String { String(String.UnicodeScalarView(scalars)) }

    /// `fresh: false` (the default) calls `reset()` first — "mid-document",
    /// so a brand-new engine's first-word capital does not muddy the check.
    init(_ config: EngineConfig, fresh: Bool = false) {
        engine = Engine(config: config)
        if !fresh { engine.reset() }
    }

    private func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { scalars.removeLast(min(r.backspaceCount, scalars.count)) }
        scalars.append(contentsOf: r.text.unicodeScalars)
    }

    // -- Vietnamese on -------------------------------------------------

    func type(_ keys: String) {
        for ch in keys { apply(engine.process(KeyInput(ch))) }
    }

    func backspace() {
        // Not composing => the Backspace passes through and deletes one
        // character the engine does not own.
        if !engine.isComposing && !scalars.isEmpty { scalars.removeLast() }
        apply(engine.process(.backspace))
    }

    /// Return: the engine commits the word, then the physical key inserts "\n".
    func newline() {
        apply(engine.flushNewline())
        scalars.append("\n")
    }

    /// An arrow/Home/End/Page key: commits the word; the caret moves but no
    /// text changes on this linear screen.
    func caretMove() { apply(engine.flushCaretMove()) }

    /// Tab: commits the word, no sentence change.
    func tab() { apply(engine.flush()) }

    // -- Vietnamese off (English-mode macros) ---------------------------

    /// Every English-mode key passes through physically: the edit first, then
    /// the typed character itself.
    func typeInactive(_ keys: String) {
        for ch in keys {
            apply(engine.processInactive(KeyInput(ch)))
            scalars.append(contentsOf: String(ch).unicodeScalars)
        }
    }

    func backspaceInactive() {
        apply(engine.processInactive(.backspace))
        if !scalars.isEmpty { scalars.removeLast() }   // the physical Delete always passes through
    }

    func caretMoveInactive() { apply(engine.flushInactiveCaretMove()) }
}

@Suite("AutoCapitalizeForgetsAfterEdit")
struct AutoCapitalizeForgetsAfterEditTests {
    private let on = EngineConfig(autoCapitalize: true)

    // -- Row 1-3: a passthrough Backspace -------------------------------

    @Test func backspaceOverPendingTerminatorForgetsIt() {
        // Row 1: "xong." leaves a confirmable "."; Backspace deletes it behind
        // the engine's back, so ", " must not confirm that stale terminator.
        let s = Screen(on)
        s.type("xong.")
        s.backspace()
        s.type(", cacs ")
        #expect(s.text == "xong, các ")
    }

    @Test func backspaceOverConfirmedSentenceStartForgetsIt() {
        // Row 2: "xong. " is a confirmed sentence start; two Backspaces eat the
        // space and the ".", so the next word is not sentence-initial.
        let s = Screen(on)
        s.type("xong. ")
        s.backspace()
        s.backspace()
        s.type(", cacs ")
        #expect(s.text == "xong, các ")
    }

    @Test func backspaceOverANewlineForgetsTheSentenceStart() {
        // Row 3: Return starts a sentence, but Backspace then deletes that
        // very "\n" — what precedes the caret is "hoa" again.
        let s = Screen(on)
        s.type("hoa")
        s.newline()
        s.backspace()
        s.type(" lan ")
        #expect(s.text == "hoa lan ")
    }

    @Test func aRetypedTerminatorStillConfirmsAfterABackspace() {
        // Row 5: `.afterReset` assumes text precedes the caret, so a terminator
        // typed after the Backspace can still confirm on following whitespace.
        let s = Screen(on)
        s.type("hoa.")
        s.backspace()
        s.type(". lan ")
        #expect(s.text == "hoa. Lan ")
    }

    @Test func backspaceInsideAComposingWordIsUnchanged() {
        // Row 6: FRESH engine. The Backspace is engine-owned (a word is
        // composing), so it edits the word and the confirmed sentence start
        // from "chaof. " survives.
        let s = Screen(on, fresh: true)
        s.type("chaof. ban")
        s.backspace()
        s.type("nj ")
        #expect(s.text == "Chào. Bạn ")
    }

    // -- Row 4: arrows / Home / End / PageUp / PageDown ----------------

    @Test func caretMoveForgetsAConfirmedSentenceStart() {
        let s = Screen(on)
        s.type("heets. ")
        s.caretMove()
        s.type("roofi ")
        #expect(s.text == "hết. rồi ")
    }

    @Test func caretMoveStillCommitsTheComposingWord() {
        // `flushCaretMove` is `finalize(boundary: nil)` first: the word being
        // composed is committed (and restored if it is English) before the
        // position is forgotten.
        let s = Screen(on)
        s.type("cacs")
        s.caretMove()
        #expect(s.text == "các")
    }

    @Test func caretMoveKeepsAFreshTerminatorConfirmable() {
        // Forgetting is `.afterReset`, not `.midSentence`: a terminator typed
        // after the arrow still opens a confirmable window.
        let s = Screen(on)
        s.type("hoa ")
        s.caretMove()
        s.type("lan. mai ")
        #expect(s.text == "hoa lan. Mai ")
    }

    @Test func tabStillNeitherConfirmsNorCancels() {
        // Guard: Tab stays `.commitPassthrough` (`flush()`), so a confirmed
        // sentence start survives it.
        let s = Screen(on)
        s.type("xong. ")
        s.tab()
        s.type("cacs ")
        #expect(s.text == "xong. Các ")
    }

    // -- Row 7: Vietnamese off (English-mode macros) --------------------

    private let macroConfig = EngineConfig(
        macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
        macros: [MacroRule(trigger: "md", replacement: "markdown",
                            expandInEnglishMode: true, autoCapitalize: true)])

    @Test func inactiveBackspaceWithEmptyBufferForgetsAPendingTerminator() {
        let s = Screen(macroConfig)
        s.typeInactive("end.")
        s.backspaceInactive()
        s.typeInactive(", md ")
        #expect(s.text == "end, markdown ")
    }

    @Test func inactiveBackspaceWithEmptyBufferForgetsAConfirmedSentenceStart() {
        let s = Screen(macroConfig)
        s.typeInactive("end. ")
        s.backspaceInactive()
        s.backspaceInactive()
        s.typeInactive(", md ")
        #expect(s.text == "end, markdown ")
    }

    @Test func inactiveBackspaceWithABufferedWordIsUnchanged() {
        // The Backspace edits the English buffer, so the sentence start from
        // "end. " is still trusted and the macro capitalizes.
        let s = Screen(macroConfig)
        s.typeInactive("end. x")
        s.backspaceInactive()
        s.typeInactive("md ")
        #expect(s.text == "end. Markdown ")
    }

    @Test func inactiveCaretMoveForgetsAConfirmedSentenceStart() {
        let s = Screen(macroConfig)
        s.typeInactive("end. ")
        s.caretMoveInactive()
        s.typeInactive("md ")
        #expect(s.text == "end. markdown ")
    }

    @Test func inactiveCaretMoveStillExpandsTheBufferedMacro() {
        // `flushInactiveCaretMove` is `matchEnglishMacro(boundary: nil)`
        // first, so a macro trigger sitting in the buffer still fires.
        let s = Screen(macroConfig)
        s.typeInactive("md")
        s.caretMoveInactive()
        #expect(s.text == "markdown")
    }
}
