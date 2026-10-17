// GraphemeDiffTests.swift — a table whose decoded output has combining marks
// (.unicodeCompound) is edited per GRAPHEME, because a Cocoa text view deletes a
// whole base+marks cluster per Backspace. A code-unit count (1 for a lone U+0301)
// would leave "t̀" on screen for Telex "tosf" and over-delete on a restore.
//
// Screens come from `Replayer.runDeletingGraphemes`. Expectations spell the
// combining marks out as escapes and compare scalars, because Swift's String ==
// treats decomposed and precomposed text as equal and would hide a wrong form.

import Testing
@testable import KeystoneEngine

@Suite("Grapheme-aware diff") struct GraphemeDiffTests {
    private func compoundConfig() -> EngineConfig {
        var config = EngineConfig()
        config.codeTable = .unicodeCompound
        return config
    }

    private func compound(_ keys: String) -> String {
        Replayer.runDeletingGraphemes(keys: keys, config: compoundConfig())
    }

    private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

    @Test func toneChangeReplacesTheWholeGrapheme() {
        #expect(scalars(compound("tosf")) == scalars("to\u{0300}"))
    }

    @Test func toneChangeInsideALongerSyllable() {
        #expect(scalars(compound("hoaf")) == scalars("ho\u{0300}a"))
    }

    @Test func qualityAndToneMarksStackOnOneBase() {
        #expect(scalars(compound("vieejt")) == scalars("vie\u{0302}\u{0323}t"))
    }

    @Test func restoreDeletesExactlyTheComposedGraphemes() {
        // "tas" showed "ta\u{0301}"; the cancel + restore must leave the raw
        // word, not "tsks" from deleting too many clusters.
        #expect(scalars(compound("tasks ")) == scalars("tasks "))
    }

    @Test func invalidWordRestoresToRawKeys() {
        #expect(scalars(compound("docker ")) == scalars("docker "))
    }

    @Test func backspaceMidWordRederivesPerGrapheme() {
        #expect(scalars(compound("tieengs\u{8}")) == scalars("tie\u{0302}ng"))
        #expect(scalars(compound("tieengs\u{8}\u{8}")) == scalars("tie\u{0302}n"))
        #expect(scalars(compound("tosf\u{8}")) == scalars("to\u{0301}"))
        #expect(scalars(compound("tosf\u{8}\u{8}")) == scalars("to"))
    }

    @Test func severalWordsInARow() {
        #expect(scalars(compound("tieengs vieejt ")) == scalars("tie\u{0302}\u{0301}ng vie\u{0302}\u{0323}t "))
    }

    @Test func toneReRenderIsOneBackspaceAndTheWholeCluster() {
        let engine = Engine(config: compoundConfig())
        for ch in "tos" { _ = engine.process(KeyInput(ch)) }
        let r = engine.process(KeyInput("f"))
        #expect(r.backspaceCount == 1)                       // one cluster, "o\u{0301}"
        #expect(scalars(r.text) == scalars("o\u{0300}"))     // retyped whole
    }

    @Test func macroExpansionErasesTheTypedWordByGrapheme() {
        var config = compoundConfig()
        config.macrosEnabled = true
        config.macros = [MacroRule(trigger: "tosf", replacement: "xin")]
        // On screen before Space: "to\u{0300}" = 2 clusters (3 scalars).
        let engine = Engine(config: config)
        for ch in "tosf" { _ = engine.process(KeyInput(ch)) }
        let r = engine.process(KeyInput(" "))
        #expect(r.backspaceCount == 2)
        #expect(r.text.hasPrefix("xin"))
    }
}
