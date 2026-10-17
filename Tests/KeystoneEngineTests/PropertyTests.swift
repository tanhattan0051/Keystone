// PropertyTests.swift — property / differential tests that don't rely on
// hand-written expected strings.
//
// 1. NFC idempotence: the engine's output for a set of valid Telex words must
//    already be in precomposed (NFC) form — no stray combining marks or
//    decomposed sequences should ever reach the screen.
// 2. Backspace-to-empty: typing a word then pressing Backspace once per RAW
//    KEYSTROKE (not once per on-screen scalar: quality and tone keys collapse
//    several raw keys into fewer scalars, and Backspace undoes one raw key and
//    re-derives the syllable) must always leave nothing on screen.

import Foundation
import Testing
@testable import KeystoneEngine

@Suite("Property") struct PropertyTests {
    /// A small hard-coded list of Telex key strings that produce valid,
    /// fully-composed Vietnamese words under the default engine config.
    static let sampleWords: [String] = [
        "vieejt",     // việt
        "hoaf",       // hoà/hòa
        "nguyeexn",   // nguyễn
        "dduwowcj",   // được
        "tieengs",    // tiếng
        "muoons",     // muốn
    ]

    @Test(arguments: PropertyTests.sampleWords)
    func nfcIdempotent(_ keys: String) {
        let c = CorpusCase(name: "nfc-\(keys)", keys: keys, expected: "")
        let out = Replayer.run(c)
        #expect(
            out == out.precomposedStringWithCanonicalMapping,
            "output for keys=\(keys) is not NFC-normalized: \(out.unicodeScalars.map { $0.value })"
        )
    }

    @Test(arguments: PropertyTests.sampleWords)
    func backspaceToEmpty(_ keys: String) {
        // The engine models Backspace as "undo one keystroke" while a word is
        // still composing: each Backspace pops one raw key and re-derives the
        // syllable (restoring diacritics/tone along the way — spec §8). So the
        // invariant is that pressing Backspace once per raw KEYSTROKE — not once
        // per on-screen scalar — always empties the buffer with no residue.
        let keystrokeCount = keys.count

        let engine = Engine(config: EngineConfig())
        var acc: [Unicode.Scalar] = []
        func apply(_ r: EngineResult) {
            if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
            acc.append(contentsOf: r.text.unicodeScalars)
        }
        for ch in keys { apply(engine.process(KeyInput(ch))) }
        for _ in 0..<keystrokeCount { apply(engine.process(.backspace)) }
        apply(engine.flush())

        #expect(acc.isEmpty, "keys=\(keys) left residue after \(keystrokeCount) backspaces: \(String(String.UnicodeScalarView(acc)))")
    }
}
