// FreeToneMarkTests.swift — TDD suite for "Cho phép bỏ dấu tự do"
// (`EngineConfig.allowFreeToneMark`), which gates the engine's *non-adjacent*
// quality-mark/đ placement (see DECISIONS.md "Positional (non-adjacent)
// marks"). ON (the default) preserves today's behavior and the full corpus;
// OFF restricts marks/đ to adjacent application only. Tones are
// syllable-level and are never affected by this flag.
//
// Uses the same replay pattern as MacroTests.swift's `typeThroughEngine`.

import Testing
@testable import KeystoneEngine

/// Replay literal keys through a fresh `Engine` and reconstruct the on-screen
/// text — copied from MacroTests.swift's private helper (same exact pattern)
/// since that one is file-private.
private func typeThroughEngine(_ keys: String, config: EngineConfig) -> String {
    let engine = Engine(config: config)
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

// MARK: - ON: non-adjacent placement works as today (Telex + VNI)

@Suite("FreeToneMarkOn")
struct FreeToneMarkOnTests {
    private let telexOn = EngineConfig(allowFreeToneMark: true)
    private let vniOn = EngineConfig(inputMethod: .vni, allowFreeToneMark: true)

    @Test func telexCircumflexPastOffglide() {
        #expect(typeThroughEngine("roiof ", config: telexOn) == "rồi ")
    }

    @Test func telexHornPastOffglide() {
        #expect(typeThroughEngine("toiws ", config: telexOn) == "tới ")
    }

    @Test func telexDStrokeOnClosedSyllable() {
        #expect(typeThroughEngine("dangd ", config: telexOn) == "đang ")
    }

    @Test func vniHornBackwardSearch() {
        #expect(typeThroughEngine("moi71 ", config: vniOn) == "mới ")
    }

    @Test func vniDStrokeOnClosedSyllable() {
        #expect(typeThroughEngine("dang9 ", config: vniOn) == "đang ")
    }
}

// MARK: - OFF: non-adjacent marks/đ don't fire (fall through to literal/restore)

@Suite("FreeToneMarkOff")
struct FreeToneMarkOffTests {
    private let telexOff = EngineConfig(allowFreeToneMark: false)
    private let vniOff = EngineConfig(inputMethod: .vni, allowFreeToneMark: false)

    // With the non-adjacent mark/đ branch suppressed, each composition below
    // never becomes a *legal* Vietnamese syllable (the circumflex/horn/đ that
    // would have fixed it up never applies), so restoreIfInvalid (on by
    // default) reverts the whole word back to its raw keystrokes at commit —
    // there is no partial "mark rejected, tone kept" state to assert instead.
    // Verified by running (see FreeToneMarkOnTests above for the ON contrast).

    @Test func telexCircumflexPastOffglideDoesNotFire() {
        #expect(typeThroughEngine("roiof ", config: telexOff) == "roiof ")
    }

    @Test func telexHornPastOffglideDoesNotFire() {
        #expect(typeThroughEngine("toiws ", config: telexOff) == "toiws ")
    }

    @Test func telexDStrokeOnClosedSyllableDoesNotFire() {
        #expect(typeThroughEngine("dangd ", config: telexOff) == "dangd ")
    }

    @Test func vniHornBackwardSearchDoesNotFire() {
        #expect(typeThroughEngine("moi71 ", config: vniOff) == "moi71 ")
    }

    @Test func vniDStrokeOnClosedSyllableDoesNotFire() {
        #expect(typeThroughEngine("dang9 ", config: vniOff) == "dang9 ")
    }

    // MARK: Adjacent marks keep working when OFF (must not regress typing)

    @Test func telexAdjacentCircumflexStillWorks() {
        #expect(typeThroughEngine("aan ", config: telexOff) == "ân ")
    }

    @Test func telexAdjacentDStrokeStillWorks() {
        #expect(typeThroughEngine("dd ", config: telexOff) == "đ ")
    }

    @Test func telexToneOnOffglideNucleusIsUnaffected() {
        // "roif" only sets a tone (huyền) on the "oi" nucleus — no circumflex
        // involved — so it is untouched by allowFreeToneMark either way.
        #expect(typeThroughEngine("roif ", config: telexOff) == "ròi ")
    }

    @Test func vniAdjacentCircumflexStillWorks() {
        #expect(typeThroughEngine("a6n ", config: vniOff) == "ân ")
    }

    @Test func vniAdjacentDStrokeStillWorks() {
        #expect(typeThroughEngine("d9 ", config: vniOff) == "đ ")
    }
}

// MARK: - Regression note: default EngineConfig() keeps free placement (corpus intact)

@Suite("FreeToneMarkDefaultRegression")
struct FreeToneMarkDefaultRegressionTests {
    @Test func defaultConfigStillYieldsFreePlacementResults() {
        // EngineConfig() is what every existing test/corpus case constructs;
        // allowFreeToneMark must default to true so this stays byte-identical.
        let telexDefault = EngineConfig()
        let vniDefault = EngineConfig(inputMethod: .vni)
        #expect(typeThroughEngine("roiof ", config: telexDefault) == "rồi ")
        #expect(typeThroughEngine("toiws ", config: telexDefault) == "tới ")
        #expect(typeThroughEngine("dangd ", config: telexDefault) == "đang ")
        #expect(typeThroughEngine("moi71 ", config: vniDefault) == "mới ")
        #expect(typeThroughEngine("dang9 ", config: vniDefault) == "đang ")
    }
}
