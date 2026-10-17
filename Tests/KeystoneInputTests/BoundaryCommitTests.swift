// BoundaryCommitTests.swift — a click, a Cmd/Ctrl/Option chord or a function
// key must finalize the word being composed (like a caret move), not drop it
// with whatever the last mid-word render happened to show.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

private let CMD_RETURN = RawKey(keyCode: 36, command: true, chars: "\r")
private let F1 = RawKey(keyCode: 122, chars: "\u{F704}")

private func apply(_ edit: EngineResult?, to acc: inout [Unicode.Scalar]) {
    guard let edit else { return }
    if edit.backspaceCount > 0 { acc.removeLast(min(edit.backspaceCount, acc.count)) }
    acc.append(contentsOf: edit.text.unicodeScalars)
}

private func screen(_ acc: [Unicode.Scalar]) -> String {
    String(String.UnicodeScalarView(acc))
}

@Suite("Boundary commit: click / chord / function key",
       .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct BoundaryCommitTests {
    // MARK: chords

    @Test func cmdReturnCommitsTheWordAsTyped() {
        let c = shippedController()
        var acc: [Unicode.Scalar] = []
        for ch in "users" { applyRealistically(c.handle(letter(ch)), to: &acc) }
        let r = c.handle(CMD_RETURN)
        applyRealistically(r, to: &acc)
        #expect(r.decision == .commitChord)
        #expect(r.suppress == false)
        #expect(screen(acc) == "users")
    }

    @Test func cmdReturnViaHelperMatchesScreen() {
        #expect(typeShipped("users", then: [CMD_RETURN]) == "users")
    }

    @Test(arguments: [
        RawKey(keyCode: 0, command: true, chars: "a"),
        RawKey(keyCode: 8, control: true, chars: "c"),
        RawKey(keyCode: 123, option: true, chars: ""),
    ])
    func chordWithNothingComposingIsANoOp(chord: RawKey) {
        let c = shippedController()
        let r = c.handle(chord)
        #expect(r.edit == nil)
        #expect(r.suppress == false)
        #expect(r.decision == .commitChord)
    }

    @Test func chordAfterWordThatCommitsToWhatItShowsRewritesNothing() {
        let c = shippedController()
        for ch in "vieetj" { _ = c.handle(letter(ch)) }
        let r = c.handle(CMD_RETURN)
        #expect(r.edit == nil)
        #expect(r.suppress == false)
    }

    // MARK: mouse

    @Test func mouseDownCommitsEnglishWordAsTyped() {
        let c = shippedController()
        var acc: [Unicode.Scalar] = []
        for ch in "test" { applyRealistically(c.handle(letter(ch)), to: &acc) }
        apply(c.handleMouseDown(), to: &acc)
        #expect(screen(acc) == "test")
    }

    @Test func mouseDownLeavesVietnameseAlone() {
        let c = shippedController()
        var acc: [Unicode.Scalar] = []
        for ch in "tieengs" { applyRealistically(c.handle(letter(ch)), to: &acc) }
        apply(c.handleMouseDown(), to: &acc)
        #expect(screen(acc) == "tiếng")
    }

    @Test func mouseDownWithNothingComposingReturnsNil() {
        #expect(shippedController().handleMouseDown() == nil)
    }

    @Test func mouseDownForgetsTheWord() {
        // After the click the next letter starts a fresh word: no backspaces
        // into the text that was committed.
        let c = shippedController()
        for ch in "vie" { _ = c.handle(letter(ch)) }
        _ = c.handleMouseDown()
        let r = c.handle(letter("e"))
        #expect((r.edit?.backspaceCount ?? 0) == 0)
    }

    @Test func mouseDownWhileInactiveClearsMacroBufferAndReturnsNil() {
        var cfg = shippedConfig
        cfg.macrosEnabled = true
        cfg.macrosExpandWhenVietnameseOff = true
        cfg.macros = [MacroRule(trigger: "ko", replacement: "không", expandInEnglishMode: true)]
        let c = shippedController(config: cfg)
        c.setActive(false)
        _ = c.handle(letter("k")); _ = c.handle(letter("o"))
        #expect(c.handleMouseDown() == nil)
        // Buffer cleared: the macro trigger no longer matches at the space.
        #expect(c.handle(SPACE).edit == nil)
    }

    // MARK: function keys

    @Test func functionKeyIsPassthroughDecision() {
        #expect(KeyTranslator.decide(F1) == .passthrough)
    }

    @Test func functionKeyCommitsWordSoNextLetterDoesNotBackspaceIntoOtherApp() {
        let c = shippedController()
        var acc: [Unicode.Scalar] = []
        for ch in "vie" { applyRealistically(c.handle(letter(ch)), to: &acc) }
        applyRealistically(c.handle(F1), to: &acc)
        let r = c.handle(letter("e"))
        #expect((r.edit?.backspaceCount ?? 0) == 0)
        applyRealistically(r, to: &acc)
        #expect(screen(acc) == "viee")
    }
}
