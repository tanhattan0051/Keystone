// CircumflexEscapeTests.swift — the "aaa"/"eee"/"ooo" circumflex escape: aa→â, and
// a third key undoes the circumflex and leaves two LITERAL letters, so "aapanel"
// (aaPanel) is typed a,a,a,p,a,n,e,l. When the word then turns out not to be
// Vietnamese, the raw restore (eager mid-word and at commit) must drop the escape
// key exactly like it already does for ddd→dd and ww→w — otherwise the screen
// jumps from "aap" to "aaapa" (three a's). See DECISIONS.md
// "The aaa/eee/ooo escape in raw-restore".

import Testing
@testable import KeystoneEngine

private let cfg = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                               freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)

private func typeThroughEngine(_ keys: String) -> String {
    let engine = Engine(config: cfg)
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

@Suite("CircumflexEscape")
struct CircumflexEscapeTests {
    @Test func aaapanelKeepsTwoAs() {
        #expect(typeThroughEngine("aaapanel ") == "aapanel ")
        #expect(typeStepwise("aaapanel") == ["a", "â", "aa", "aap", "aapa", "aapan", "aapane", "aapanel"])
    }
    @Test func reportedKeysAaapenl() {
        #expect(typeThroughEngine("aaapenl ") == "aapenl ")
        #expect(!typeStepwise("aaapenl").contains { $0.hasPrefix("aaa") })
    }
    @Test func eeeAndOooEscapes() {
        #expect(typeThroughEngine("eeexit ") == "eexit ")
        #expect(typeThroughEngine("ooops ") == "oops ")
    }
    @Test func screenBeforeSpaceMatchesCommit() {
        // "aaa" alone shows "aa"; Space must not grow it back to three.
        #expect(typeStepwise("aaa") == ["a", "â", "aa"])
        #expect(typeThroughEngine("aaa ") == "aa ")
    }
    // Regression: Vietnamese circumflex words and plain doubles are unchanged.
    @Test func vietnameseUnaffected() {
        #expect(typeThroughEngine("caan ") == "cân ")
        #expect(typeThroughEngine("treen ") == "trên ")
        #expect(typeThroughEngine("hoojp ") == "hộp ")
        #expect(typeThroughEngine("tana ") == "tân ")
        #expect(typeThroughEngine("aapanel ") == "aapanel ")
        #expect(typeThroughEngine("dddos ") == "ddos ")
    }

    // Fold: which keys undid a circumflex.
    @Test func foldRecordsCircumflexUndoKeys() {
        #expect(Telex.fold(Array("aaa"), literalAfterCancel: true).circumflexUndoKeys == [2])
        #expect(Telex.fold(Array("tanaa"), freeMarkAcrossCoda: true, literalAfterCancel: true)
                    .circumflexUndoKeys == [4])
        #expect(Telex.fold(Array("tassaaa"), literalAfterCancel: true).circumflexUndoKeys == [])
    }

    // No jump at Space: the commit equals the last screen.
    @Test(arguments: ["tassaaa", "wwaaa", "dddooo", "arrooow", "whenceeer", "freeext", "noooooo",
                      "AAa", "aAa", "aaA", "aAaapanel", "tanaa", "IEEE", "aaaa", "aaaaa",
                      "caaan", "hooojp"])
    func commitEqualsLastScreen(_ w: String) {
        #expect(typeThroughEngine(w + " ") == typeStepwise(w).last! + " ")
    }

    // Escapes that are NOT circumflex undos keep main's commit.
    @Test func nonEscapeRunsKeepMainsCommit() {
        #expect(typeThroughEngine("tassaaa ") == "tassaaa ")
        #expect(typeThroughEngine("wwaaa ") == "waaa ")
        #expect(typeThroughEngine("dddooo ") == "ddooo ")
        #expect(typeThroughEngine("whenceeer ") == "whenceeer ")
        #expect(typeThroughEngine("freeext ") == "freeext ")
    }
    @Test func caseOfKeyOneAndThreeIsKept() {
        #expect(typeThroughEngine("AAa ") == "Aa ")
        #expect(typeThroughEngine("aAa ") == "aa ")
        #expect(typeThroughEngine("aaA ") == "aA ")
    }

    // An across-coda undo (t,a,n,a,a) is a fold fact but not a literal run, so the
    // raw restore keeps main's behavior (engine without lexicon: "tanaa" on screen and at commit, same as main).
    @Test func acrossCodaUndoKeepsMainsBehavior() {
        #expect(typeThroughEngine("tanaa ") == "tanaa ")
    }
}
