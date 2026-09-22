// DStrokeEscapeTests.swift — the "ddd" đ-escape: typing three d's means two
// LITERAL d's (dd→đ, the third d undoes the đ and leaves "dd"), so an English/
// tech word whose intended literal starts with "dd" is typed with a leading
// "ddd". The raw-restore that reverts an invalid word to its keystrokes must
// collapse that escape (ddd→dd) the same way it already collapses the horn
// escape (ww→w) — otherwise "dddos" (for DDoS) reverts to the raw "dddos"
// (an extra d) instead of the intended "ddos". "ddos" alone is the common
// Vietnamese word "đó" (identical keystrokes), so the ddd-escape is the only
// way to get the literal. See DECISIONS.md "The ddd→dd escape in raw-restore".

import Testing
@testable import KeystoneEngine

private let cfg = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                               freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)

private func typeThroughEngine(_ keys: String, lexicon: Lexicon? = nil) -> String {
    let engine = Engine(config: cfg); engine.lexicon = lexicon
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    for ch in keys { apply(engine.process(KeyInput(ch))) }
    apply(engine.flush())
    return String(String.UnicodeScalarView(acc))
}
private func typeStepwise(_ keys: String) -> [String] {
    let engine = Engine(config: cfg)
    var acc: [Unicode.Scalar] = []; var steps: [String] = []
    for ch in keys {
        let r = engine.process(KeyInput(ch))
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
        steps.append(String(String.UnicodeScalarView(acc)))
    }
    return steps
}

@Suite("DStrokeEscape")
struct DStrokeEscapeTests {
    @Test func dddosEscapesToDdos() {
        #expect(typeThroughEngine("dddos ") == "ddos ")
        #expect(typeStepwise("dddos") == ["d", "đ", "dd", "ddo", "ddos"])
    }
    @Test func dddongEscapesToDdong() {
        #expect(typeThroughEngine("dddong ") == "ddong ")
    }
    @Test func ddaloneEscapesToDd() {
        // Two literal d's on their own: still "dd" (no vowel → kept as composed).
        #expect(typeThroughEngine("ddd ") == "dd ")
    }
    // Regression: words WITHOUT a "ddd" run are untouched.
    @Test func plainDoubledDUnaffected() {
        #expect(typeThroughEngine("add ") == "add ")
        #expect(typeThroughEngine("buddy ") == "buddy ")
        #expect(typeThroughEngine("boss ") == "boss ")   // tone-key double, not a d-escape
        #expect(typeThroughEngine("wwin ") == "win ")     // ww→w still works
    }
    // The bare word still collides with Vietnamese "đó" (can't be fixed).
    @Test func plainDdosStillComposesToVietnamese() {
        #expect(typeThroughEngine("ddos ") == "đó ")
    }
}
