// TapGapAndOptionCharTests.swift — (D) the engine buffer is dropped when the OS
// disables the tap, and (H) Option-produced characters commit and pass through.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("Tap disabled gap")
struct TapGapTests {
    @Test func interruptionDropsTheComposingWord() {
        let engine = EngineController(config: shippedConfig)
        let tap = EventTapController(engine: engine)
        for ch in "tie" { _ = engine.handle(letter(ch)) }
        tap.tapWasInterrupted()
        // Without the reset, this `e` would rewrite the screen's "tie" to "tiê".
        let r = engine.handle(letter("e"))
        #expect(r.edit?.backspaceCount == 0)
        #expect(r.edit?.text == "e")
    }
}

@Suite("Option-produced characters", .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct OptionCharTests {
    private let optionAt = RawKey(keyCode: 19, option: true, chars: "@")

    @Test func optionCharCommitsWordAndPassesThrough() {
        let c = shippedController()
        var screen: [Unicode.Scalar] = []
        for ch in "users" { applyRealistically(c.handle(letter(ch)), to: &screen) }
        let r = c.handle(optionAt)
        #expect(!r.suppress)
        #expect(r.decision == .commitChord)
        applyRealistically(r, to: &screen)
        #expect(String(String.UnicodeScalarView(screen)) == "users")
    }

    @Test func optionCharAfterTelexWordCommitsComposedWord() {
        let c = shippedController()
        var screen: [Unicode.Scalar] = []
        for ch in "tieengs" { applyRealistically(c.handle(letter(ch)), to: &screen) }
        let r = c.handle(optionAt)
        #expect(!r.suppress)
        applyRealistically(r, to: &screen)
        #expect(String(String.UnicodeScalarView(screen)) == "tiếng")
    }
}
