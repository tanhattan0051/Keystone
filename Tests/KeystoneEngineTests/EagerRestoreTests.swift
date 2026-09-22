// EagerRestoreTests.swift — TDD suite for `EngineConfig.spellCheck`'s EAGER
// RESTORE behavior ("Kiểm tra chính tả"): while the user is still typing, as
// soon as the composing word becomes a Vietnamese syllable that is DEAD
// (structurally unrecoverable — no possible continuation can ever make it a
// legal syllable), `Engine.rerender` renders the RAW keystrokes literally
// instead of the Vietnamese-composed form. This makes English words like
// `docker`/`vmware`/`faster` show as themselves AS YOU TYPE, instead of
// flashing Vietnamese (e.g. `docker` currently shows `dỏcke` until Space).
//
// This is a STRICTER, EARLIER cousin of the existing word-boundary
// restore-if-invalid in `Engine.finalize` — see DECISIONS.md "Eager restore
// (spellCheck / Phase 7)". The hard safety requirement: with `spellCheck` on,
// every REAL Vietnamese word must render byte-identical, stepwise AND at the
// boundary, to `spellCheck` off. A "currently invalid" check is NOT enough —
// ~13% of real Vietnamese words are temporarily invalid mid-typing (e.g.
// `môt`→một, `ngươ`→người, `tâp`→tập) and recover on a later keystroke; only
// a DEAD/unrecoverable composition may trigger eager restore. That's why
// `EagerRestoreVietnameseUnaffectedTests` below is the load-bearing suite.
//
// Uses the same replay pattern as LiteralAfterCancelTests.swift's
// `typeThroughEngine`/`typeStepwise` (copied here for the same reason: those
// helpers are file-private there).

import Testing
@testable import KeystoneEngine

private func typeThroughEngine(_ keys: String, config: EngineConfig, lexicon: Lexicon? = nil) -> String {
    let engine = Engine(config: config)
    engine.lexicon = lexicon
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

/// Screen contents after EACH key of `keys` (no trailing flush) — for
/// asserting a full per-keystroke trace.
private func typeStepwise(_ keys: String, config: EngineConfig, lexicon: Lexicon? = nil) -> [String] {
    let engine = Engine(config: config)
    engine.lexicon = lexicon
    var acc: [Unicode.Scalar] = []
    var steps: [String] = []
    for ch in keys {
        let r = engine.process(KeyInput(ch))
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
        steps.append(String(String.UnicodeScalarView(acc)))
    }
    return steps
}

private let on = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                               freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)
private let off = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                                freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: false)

// MARK: - spellCheck ON fixes the mid-word English "flash"

@Suite("EagerRestoreFixesEnglishFlash")
struct EagerRestoreFixesEnglishFlashTests {
    @Test(arguments: [
        "docker", "vmware", "faster", "folder", "master",
    ])
    func stepwiseLastElementIsTheLiteralWord(word: String) {
        #expect(typeStepwise(word, config: on).last == word)
    }

    @Test func dockerFullStepwiseTrace() {
        // Pinned exact per-keystroke trace: "dock" (4 keys) is already dead
        // (coda "ck" is neither a legal coda nor the prefix of one), so from
        // that key on every step renders the raw keystrokes literally.
        let steps = typeStepwise("docker", config: on)
        #expect(steps == ["d", "do", "doc", "dock", "docke", "docker"])
    }
}

// MARK: - Final (word-boundary) output is unchanged by the flag

@Suite("EagerRestoreFinalUnchanged")
struct EagerRestoreFinalUnchangedTests {
    @Test(arguments: [
        "docker", "vmware", "faster", "folder", "master", "class", "press",
    ])
    func finalOutputSameOnAndOff(word: String) {
        let expected = word + " "
        #expect(typeThroughEngine(word + " ", config: on) == expected)
        #expect(typeThroughEngine(word + " ", config: off) == expected)
    }
}

// MARK: - THE SAFETY GATE: Vietnamese typing is completely unaffected

@Suite("EagerRestoreVietnameseUnaffected")
struct EagerRestoreVietnameseUnaffectedTests {
    // 21 known-tricky recoverable-intermediate cases (temporarily invalid
    // mid-word, but recover on a later key) plus a broader natural-typing
    // sample — none of these may EVER diverge between spellCheck on/off.
    @Test(arguments: [
        "nguowif", "truowngf", "ddepj", "nuowcs", "mootj", "suowng", "taapj", "taats",
        "huowu", "ruowuj", "cuowif", "tuyeets", "quyeets", "vuownf", "muowngf", "dduowngf",
        "dduowcj", "quoocs", "thuowr", "huowngf", "tiseeng",
        "hoaf", "khoer", "thuyr", "toans", "tuaanf", "tieengs", "muoons", "cuar", "mias",
        "quar", "giayf", "khuyur", "nguyeexn", "hoangf", "roiof", "loiox", "toio", "moio",
        "doiox", "noio", "ngoaos", "ngoeor", "khoais", "caof", "dangd", "huow", "khuow",
        "thuowr", "ddang", "dieendf", "toiws", "moiws", "guiwr", "nuawx", "cuaw", "muaw",
        "cangw", "quawng", "vieejt", "yeeu", "nguowif", "hocj", "phowr", "ddepj",
        "nuowcs", "mootj", "beef", "bees",
    ])
    func vietnameseWordIdenticalStepwiseAndFinal(word: String) {
        #expect(typeStepwise(word, config: on) == typeStepwise(word, config: off))
        #expect(typeThroughEngine(word + " ", config: on) == typeThroughEngine(word + " ", config: off))
    }

    // Each corpus fixture, run in ITS OWN configured mode (so quickTelex
    // fixtures keep quickTelex on, etc.), with only `spellCheck` toggled.
    private func onOffConfigs(_ c: CorpusCase) -> (on: EngineConfig, off: EngineConfig) {
        var on = c.engineConfig; on.spellCheck = true
        var off = c.engineConfig; off.spellCheck = false
        return (on, off)
    }
    private var telexCorpus: [CorpusCase] {
        ["words", "words2", "diacritics", "placement", "positional", "tones", "quicktelex"]
            .flatMap { CorpusLoader.load($0) }
            .filter { ($0.method ?? "telex") == "telex" && !$0.keys.contains(" ") && !$0.keys.contains("\u{8}") }
    }

    // INVARIANT 1 (universal): the committed word-boundary output is IDENTICAL
    // on vs. off for EVERY fixture, no exceptions. `Engine.finalize` never
    // reads `spellCheck` — eager restore only changes MID-WORD rendering, and
    // finalize recomputes the final units from `rawKeys` regardless of what
    // was shown while typing. So the flag can never change what actually
    // commits. Zero divergences, no allowlist.
    @Test func corpusFinalOutputIdenticalOnAndOff() {
        let cases = telexCorpus
        var bad: [(String, String, String)] = []
        for c in cases {
            let (on, off) = onOffConfigs(c)
            let fon = typeThroughEngine(c.keys, config: on)
            let foff = typeThroughEngine(c.keys, config: off)
            if fon != foff { bad.append((c.keys, fon, foff)) }
        }
        #expect(bad.isEmpty, "final output diverged on/off: \(bad)")
        #expect(!cases.isEmpty)
    }

    // INVARIANT 2 (the load-bearing safety gate): for every fixture whose
    // EXPECTED result is an actual Vietnamese word (carries a Vietnamese-
    // specific character — đ or any toned/quality-marked vowel, i.e. a
    // non-ASCII scalar), the FULL per-keystroke trace is identical on vs. off.
    // A real Vietnamese word is never "dead" at any prefix by construction, so
    // eager restore must never fire while typing one. Zero divergences.
    // (ASCII-only fixtures like the "ddd"→"dd" / "ass"→"as" double-strike
    // probes are English/mechanism escapes, not Vietnamese words, and are
    // deliberately outside this gate — their final output is still pinned
    // identical by INVARIANT 1 above.)
    @Test func corpusVietnameseStepwiseIdenticalOnAndOff() {
        let cases = telexCorpus.filter { $0.expected.unicodeScalars.contains { $0.value > 0x7F } }
        var bad: [(String, [String], [String])] = []
        for c in cases {
            let (on, off) = onOffConfigs(c)
            let son = typeStepwise(c.keys, config: on)
            let soff = typeStepwise(c.keys, config: off)
            if son != soff { bad.append((c.keys, son, soff)) }
        }
        #expect(bad.isEmpty, "Vietnamese-word stepwise diverged on/off: \(bad)")
        #expect(!cases.isEmpty)
    }
}

// MARK: - spellCheck OFF is exactly today's behavior

@Suite("EagerRestoreOffIsTodayBehavior")
struct EagerRestoreOffIsTodayBehaviorTests {
    @Test func dockerStaysComposedMidWordWhenOff() {
        // Pins today's actual (pre-feature) composed text: the trailing "r"
        // is Telex's hỏi tone key and lands (non-adjacently) on the "o"
        // instead of appending as its own letter.
        #expect(typeStepwise("docker", config: off).last == "dỏcke")
    }
}
