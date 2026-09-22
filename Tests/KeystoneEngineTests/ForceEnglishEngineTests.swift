// ForceEnglishEngineTests.swift — engine-level TDD suite exercising
// `Engine.forceEnglish` directly (in isolation from `EngineController`/
// `SupplementaryWords`), proving the `finalize` mechanism itself: when
// `config.spellCheck` is on and the just-typed raw word is in
// `Engine.forceEnglish`, the raw English literal commits even though the
// Vietnamese composition is perfectly valid. See DECISIONS.md "Force-English
// whitelist (Lớp B)" and Tests/KeystoneInputTests/ForceEnglishTests.swift for
// the full app-facing suite against the real curated list.

import Testing
@testable import KeystoneEngine

private func typeThroughEngine(_ keys: String, config: EngineConfig, forceEnglish: Lexicon? = nil) -> String {
    let engine = Engine(config: config)
    engine.forceEnglish = forceEnglish
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    for ch in keys {
        apply(engine.process(KeyInput(ch)))
    }
    apply(engine.flush())
    return String(String.UnicodeScalarView(acc))
}

private let on = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                               freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)
private let off = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                                freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: false)

@Suite("EngineForceEnglish")
struct EngineForceEnglishTests {
    private let tiny = Lexicon(["test", "reset"])

    @Test func wordInForceEnglishListWinsOverValidVietnameseComposition() {
        #expect(typeThroughEngine("test", config: on, forceEnglish: tiny) == "test")
        #expect(typeThroughEngine("reset", config: on, forceEnglish: tiny) == "reset")
    }

    @Test func wordNotInForceEnglishListStillComposesVietnamese() {
        // "six" would also collide with a Vietnamese syllable, but it's not
        // in this tiny test list, so it must compose normally.
        #expect(typeThroughEngine("six", config: on, forceEnglish: tiny) == "sĩ")
    }

    @Test func inertWithNoForceEnglishListInstalled() {
        #expect(typeThroughEngine("test", config: on, forceEnglish: nil) == "tét")
    }

    @Test func inertWhenSpellCheckIsOff() {
        #expect(typeThroughEngine("test", config: off, forceEnglish: tiny) == "tét")
    }

    @Test func capitalizationFromAutoCapitalizeIsPreservedOnTheForcedEnglishWord() {
        var cfg = on
        cfg.autoCapitalize = true
        #expect(typeThroughEngine("test", config: cfg, forceEnglish: tiny) == "Test")
    }
}
