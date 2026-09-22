// DeferredCircumflexTests.swift — the across-coda circumflex (freeMarkAcrossCoda)
// is applied ONLY at the word boundary (Engine.finalize, `committing: true`),
// never in the per-keystroke Engine.rerender. So `tana`/`trene` stay literal
// WHILE typing and become `tân`/`trên` only at commit — and an English word
// with the same V-C-V shape (`manager`) never flashes pseudo-Vietnamese
// (`mân`/`mâng`) mid-word. The within-nucleus circumflex (aa→â), the đ-stroke
// and tone marks all stay EAGER (applied per keystroke). See DECISIONS.md
// "Deferred across-coda circumflex (smooth typing)".

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

// MARK: - Across-coda circumflex is DEFERRED: literal mid-word, no flash

@Suite("AcrossCodaCircumflexDeferredMidWord")
struct AcrossCodaCircumflexDeferredMidWordTests {
    @Test func tanaStaysLiteralUntilCommit() {
        #expect(typeStepwise("tana").last == "tana")   // NOT "tân" mid-word
    }
    @Test func treneStaysLiteralUntilCommit() {
        #expect(typeStepwise("trene").last == "trene")  // NOT "trên" mid-word
    }
    @Test func englishManagerNeverFlashesVietnamese() {
        // The whole point: no "mân"/"mâng" ever appears while typing.
        #expect(typeStepwise("manager") == ["m","ma","man","mana","manag","manage","manager"])
    }
}

// MARK: - ...but the mark IS applied at the word boundary (commit)

@Suite("AcrossCodaCircumflexAppliedAtCommit")
struct AcrossCodaCircumflexAppliedAtCommitTests {
    @Test func tanaCommitsToTan()   { #expect(typeThroughEngine("tana ") == "tân ") }
    @Test func treneCommitsToTren() { #expect(typeThroughEngine("trene ") == "trên ") }
    @Test func tanafCommitsToTan()  { #expect(typeThroughEngine("tanaf ") == "tần ") }
    @Test func managerCommitsToEnglish() {
        // At commit it folds to the invalid "mânger" and reverts to raw.
        #expect(typeThroughEngine("manager ") == "manager ")
    }
}

// MARK: - Eager marks unchanged: adjacent circumflex, đ-stroke, tones

@Suite("EagerMarksStillImmediate")
struct EagerMarksStillImmediateTests {
    @Test func adjacentCircumflexImmediate() {
        #expect(typeStepwise("caan") == ["c","ca","câ","cân"])
        #expect(typeStepwise("treen") == ["t","tr","tre","trê","trên"])
    }
    @Test func dStrokeImmediate() {
        #expect(typeStepwise("dadx") == ["d","da","đa","đã"])
        #expect(typeStepwise("dadng") == ["d","da","đa","đan","đang"])
    }
    @Test func tonesImmediate() {
        #expect(typeStepwise("toans").last == "toán")
        #expect(typeStepwise("camr").last == "cảm")
    }
}
