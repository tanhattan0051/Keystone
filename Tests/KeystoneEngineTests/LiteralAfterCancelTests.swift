// LiteralAfterCancelTests.swift — TDD suite for `EngineConfig.literalAfterCancel`,
// the OpenKey-compatible cancel semantics (Phase 6): once a Telex/VNI tone or
// quality-mark CANCEL (the standard same-key double-strike — Telex ss/ff/rr/
// xx/jj tones, aa/ee/oo circumflex, dd's đ-stroke, w's horn/breve undo; VNI
// digits 1-5 tones and 6/7/8/9 marks the same way) fires anywhere in the
// composing word, every LATER key of that word is taken completely
// literally — no tone, no quality mark, no quick-telex/quick-consonant
// transform — until the word boundary. See DECISIONS.md "OpenKey-compatible
// literal-after-cancel (Phase 6)" and `Sources/KeystoneEngine/Telex.swift`/
// `VNI.swift`'s `fold` doc comments (the `cancelled` local).
//
// `z` (tone-clear) is deliberately NOT a cancel under this rule (it never
// doubles a letter to undo anything, see DECISIONS.md "`z` key semantics"),
// so it is not exercised here as a trigger.
//
// Uses the same replay pattern as MacroTests.swift's `typeThroughEngine`
// (copied here since that helper is file-private there — same pattern as
// EngineTogglesTests.swift/FreeMarkAcrossCodaTests.swift).

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
/// asserting a full per-keystroke trace, matching the style of the
/// background per-key tables this feature is built from.
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

/// The small in-test lexicon the task spec calls for: just the words these
/// tests actually need, both sides of the cancel-habit table plus the
/// natural-typing sanity words.
private let testLexicon = Lexicon([
    "pass", "class", "miss", "less", "press", "task", "fix", "google", "test", "off",
    "offer", "coffee", "assess", "classes", "passed",
])

// MARK: - Per-keystroke trace (flag ON) — mirrors the background table

@Suite("LiteralAfterCancelPerKeystrokeTrace")
struct LiteralAfterCancelPerKeystrokeTraceTests {
    private let on = EngineConfig(restoreIfInvalid: true, literalAfterCancel: true)

    @Test func classssTrace() {
        // c, l, a, s(tone), s(CANCEL), s(now literal, not a re-toggle) — the
        // OpenKey habit: press the mark key once more after seeing it
        // toggled off, and everything from there on is literal.
        let steps = typeStepwise("classs", config: on)
        #expect(steps == ["c", "cl", "cla", "clá", "clas", "class"])
    }

    @Test func classssCommitsToClassViaLexicon() {
        // "class" (5 letters) isn't a legal Vietnamese onset ("cl"), so it
        // still needs restoreIfInvalid + the lexicon to pick the composed
        // spelling over the raw "classs" — see RestoreDecision.
        #expect(typeThroughEngine("classs ", config: on, lexicon: testLexicon) == "class ")
    }

    @Test func offffTrace() {
        // o, f(tone huyền), f(CANCEL), f(literal, not a re-toggle).
        let steps = typeStepwise("offf", config: on)
        #expect(steps == ["o", "ò", "of", "off"])
    }
}

// MARK: - Before the cancel fires, behavior is byte-identical to flag OFF

@Suite("LiteralAfterCancelUnchangedBeforeTheCancel")
struct LiteralAfterCancelUnchangedBeforeTheCancelTests {
    @Test func sameStepsUpToAndIncludingTheCancelKeystroke() {
        let on = EngineConfig(literalAfterCancel: true)
        let off = EngineConfig(literalAfterCancel: false)
        // "clas" (4 keys: c,l,a,s) — only ONE 's', no cancel possible yet.
        #expect(typeStepwise("clas", config: on) == typeStepwise("clas", config: off))
        // "class" (5 keys) — the cancel fires on this very last key; the
        // steps up to and including it are still identical, only what
        // happens to a key typed AFTER this one would differ.
        #expect(typeStepwise("class", config: on) == typeStepwise("class", config: off))
    }
}

// MARK: - Flag ON + restoreIfInvalid ON + lexicon: the OpenKey cancel habit

@Suite("LiteralAfterCancelFixesOpenKeyCancelHabit")
struct LiteralAfterCancelFixesOpenKeyCancelHabitTests {
    private let config = EngineConfig(restoreIfInvalid: true, literalAfterCancel: true)

    @Test(arguments: [
        ("passs", "pass"), ("classs", "class"), ("misss", "miss"), ("lesss", "less"),
        ("presss", "press"), ("tassk", "task"), ("fixx", "fix"), ("gooogle", "google"),
        ("tesst", "test"), ("offf", "off"), ("Tassk", "Task"),
    ])
    func cancelHabitCommitsToTheIntendedWord(raw: String, expected: String) {
        #expect(typeThroughEngine(raw + " ", config: config, lexicon: testLexicon) == expected + " ")
    }

    @Test func worksEvenWithoutRestoreIfInvalidOrALexicon() {
        // The flag alone (no lexicon, no restore-if-invalid) already builds
        // the right spelling character-for-character once literal mode
        // kicks in — restore/lexicon isn't what fixes this, it just also
        // doesn't get in the way.
        let bare = EngineConfig(restoreIfInvalid: false, literalAfterCancel: true)
        #expect(typeThroughEngine("classs ", config: bare) == "class ")
        #expect(typeThroughEngine("passs ", config: bare) == "pass ")
        #expect(typeThroughEngine("offf ", config: bare) == "off ")
    }
}

// MARK: - Flag OFF: exactly today's behavior, unchanged

@Suite("LiteralAfterCancelOffPreservesTodayBehavior")
struct LiteralAfterCancelOffPreservesTodayBehaviorTests {
    private let config = EngineConfig(restoreIfInvalid: true, literalAfterCancel: false)

    // Words where the trailing key after the cancel is itself the SAME
    // transform key (another s/f) — Telex re-toggles it instead of leaving
    // it literal, so raw-restore's extra letter survives: this is the bug
    // this feature exists to fix, and OFF must keep reproducing it exactly.
    @Test(arguments: [
        ("passs", "passs"), ("classs", "classs"), ("misss", "misss"),
        ("lesss", "lesss"), ("presss", "presss"), ("offf", "offf"),
    ])
    func stillDoublesTheCancelHabitLetter(raw: String, expectedStillBroken: String) {
        #expect(typeThroughEngine(raw + " ", config: config, lexicon: testLexicon)
                 == expectedStillBroken + " ")
    }

    // Words where the trailing key after the cancel ISN'T itself a Telex
    // transform key (k, x-end, l/e, t) — these already commit correctly via
    // the existing lexicon restore alone, flag or no flag.
    @Test(arguments: [
        ("tassk", "task"), ("fixx", "fix"), ("gooogle", "google"),
        ("tesst", "test"), ("Tassk", "Task"),
    ])
    func alreadyFixedByLexiconRestoreAlone(raw: String, expected: String) {
        #expect(typeThroughEngine(raw + " ", config: config, lexicon: testLexicon) == expected + " ")
    }

    @Test func composedShapeWithoutRestoreOrLexiconIsTheOldBrokenOne() {
        // Pins today's actual (pre-restore) composed text for the
        // re-toggling words: the cancel key re-applies its tone instead of
        // staying literal.
        let bare = EngineConfig(restoreIfInvalid: false, literalAfterCancel: false)
        #expect(typeThroughEngine("classs", config: bare) == "clás")
        #expect(typeThroughEngine("passs", config: bare) == "pás")
        #expect(typeThroughEngine("offf", config: bare) == "òf")
    }
}

// MARK: - Natural typing (no deliberate extra cancel keystroke) is unaffected

@Suite("LiteralAfterCancelNaturalTypingUnaffected")
struct LiteralAfterCancelNaturalTypingUnaffectedTests {
    @Test(arguments: [
        ("pass", "pass"), ("class", "class"), ("miss", "miss"), ("task", "task"),
        ("google", "google"), ("offer", "offer"), ("coffee", "coffee"),
        ("assess", "assess"), ("classes", "classes"), ("passed", "passed"),
    ])
    func naturalEnglishWordsUnaffectedByFlag(raw: String, expected: String) {
        let on = EngineConfig(restoreIfInvalid: true, literalAfterCancel: true)
        let off = EngineConfig(restoreIfInvalid: true, literalAfterCancel: false)
        #expect(typeThroughEngine(raw + " ", config: on, lexicon: testLexicon) == expected + " ")
        #expect(typeThroughEngine(raw + " ", config: off, lexicon: testLexicon) == expected + " ")
    }

    @Test func testWordStaysTetByExistingTelexDesignNotChangedHere() {
        // "test" has only ONE natural "s" — no double-strike, so no cancel
        // ever fires. Telex's tone key still applies sắc to "e" by design
        // (unrelated to this feature): current behavior, asserted as-is per
        // the task spec ("assert the current behavior, don't change it").
        let on = EngineConfig(restoreIfInvalid: true, literalAfterCancel: true)
        let off = EngineConfig(restoreIfInvalid: true, literalAfterCancel: false)
        #expect(typeThroughEngine("test ", config: on, lexicon: testLexicon) == "tét ")
        #expect(typeThroughEngine("test ", config: off, lexicon: testLexicon) == "tét ")
    }
}

// MARK: - Backspace past the cancel keystroke drops literal mode

@Suite("LiteralAfterCancelBackspacePastCancelResets")
struct LiteralAfterCancelBackspacePastCancelResetsTests {
    // No lexicon/restore needed — this is purely about what `rerender`
    // re-derives from `rawKeys`, and confirms the design note: "if the
    // engine re-renders from rawKeys this falls out naturally."
    private let config = EngineConfig(literalAfterCancel: true)

    @Test func deletingThroughTheCancelKeyLetsItRetriggerNormally() {
        let engine = Engine(config: config)
        var acc: [Unicode.Scalar] = []
        func apply(_ r: EngineResult) {
            if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
            acc.append(contentsOf: r.text.unicodeScalars)
        }
        func screen() -> String { String(String.UnicodeScalarView(acc)) }

        for ch in "tassk" { apply(engine.process(KeyInput(ch))) }
        #expect(screen() == "task")   // t,a,s(tone),s(CANCEL->literal s),k(literal, flag on)

        apply(engine.process(.backspace))   // remove the literal "k"
        #expect(screen() == "tas")

        apply(engine.process(.backspace))   // remove the CANCEL "s" itself
        #expect(screen() == "tá")           // back to a single toned "s" state

        // Literal mode must be OFF now: retyping "s" re-triggers a FRESH
        // cancel (not treated as already-literal), reproducing the exact
        // pre-backspace state.
        apply(engine.process(KeyInput("s")))
        #expect(screen() == "tas")

        apply(engine.process(KeyInput("k")))
        #expect(screen() == "task")
    }
}

// MARK: - VNI parity: digit-doubling cancel also suppresses later transforms

@Suite("LiteralAfterCancelVNIParity")
struct LiteralAfterCancelVNIParityTests {
    @Test func digitCancelSuppressesALaterCircumflexDigit() {
        // t, e, 1(sắc), 1(CANCEL -> literal "1"), 6(circumflex on e) — with
        // the flag OFF (today), "6" reaches backward past the literal "1"
        // and circumflexes the earlier "e" anyway; with the flag ON, "6" is
        // forced literal too, since it comes after the cancel.
        let on = EngineConfig(inputMethod: .vni, restoreIfInvalid: false, literalAfterCancel: true)
        let off = EngineConfig(inputMethod: .vni, restoreIfInvalid: false, literalAfterCancel: false)
        #expect(typeThroughEngine("te116", config: on) == "te16")
        #expect(typeThroughEngine("te116", config: off) == "tê1")
    }

    @Test func stepwiseTraceShowsExactlyWhereTheDivergenceStarts() {
        let on = EngineConfig(inputMethod: .vni, literalAfterCancel: true)
        let off = EngineConfig(inputMethod: .vni, literalAfterCancel: false)
        let onSteps = typeStepwise("te116", config: on)
        let offSteps = typeStepwise("te116", config: off)
        // Identical through the cancel keystroke (index 3, the second "1")...
        #expect(Array(onSteps.prefix(4)) == Array(offSteps.prefix(4)))
        #expect(onSteps[3] == "te1")
        // ...and diverge only on the very next key.
        #expect(onSteps[4] == "te16")
        #expect(offSteps[4] == "tê1")
    }

    @Test func restoreIfInvalidOnWithNoMatchingLexiconWordStillFallsBackToRawEitherWay() {
        // Neither "te16" nor "tê1" is a legal Vietnamese syllable (coda
        // "16"/trailing "1" isn't a real coda) or in any lexicon, so with
        // restoreIfInvalid on both revert to the raw digits regardless of
        // the flag — the flag changes the COMPOSED shape, not whether an
        // invalid word still reverts.
        let on = EngineConfig(inputMethod: .vni, restoreIfInvalid: true, literalAfterCancel: true)
        let off = EngineConfig(inputMethod: .vni, restoreIfInvalid: true, literalAfterCancel: false)
        #expect(typeThroughEngine("te116 ", config: on) == "te116 ")
        #expect(typeThroughEngine("te116 ", config: off) == "te116 ")
    }
}

// MARK: - Vietnamese typing is completely unchanged, flag on or off

@Suite("LiteralAfterCancelVietnameseUnchanged")
struct LiteralAfterCancelVietnameseUnchangedTests {
    // ~60 Telex words sampled straight from the existing pinned corpus
    // (Corpus/diacritics.json, placement.json, positional.json, words.json,
    // words2.json) — none of these ever reach a same-key double-strike
    // CANCEL (the aa/ee/oo/dd/w/tone-key pairs here are ordinary mark
    // APPLICATIONS, not undo-then-redo triples), so `literalAfterCancel`
    // must be a complete no-op on every one of them.
    @Test(arguments: [
        ("hoaf", "hòa"), ("khoer", "khỏe"), ("thuyr", "thủy"), ("toans", "toán"),
        ("tuaanf", "tuần"), ("tieengs", "tiếng"), ("muoons", "muốn"), ("dduowcj", "được"),
        ("cuar", "của"), ("mias", "mía"), ("quar", "quả"), ("giayf", "giày"),
        ("khuyur", "khuỷu"), ("nguyeexn", "nguyễn"), ("hoangf", "hoàng"), ("quoocs", "quốc"),
        ("roiof", "rồi"), ("loiox", "lỗi"), ("toio", "tôi"), ("moio", "môi"),
        ("doiox", "dỗi"), ("noio", "nôi"), ("rooif", "rồi"), ("looix", "lỗi"),
        ("ngoaos", "ngoáo"), ("ngoeor", "ngoẻo"), ("khoais", "khoái"), ("caof", "cào"),
        ("dangd", "đang"), ("huow", "huơ"), ("khuow", "khuơ"), ("thuowr", "thuở"),
        ("huowngf", "hường"), ("ddang", "đang"), ("dieendf", "điền"), ("toiws", "tới"),
        ("moiws", "mới"), ("guiwr", "gửi"), ("chuiwr", "chửi"), ("nguiwr", "ngửi"),
        ("nuawx", "nữa"), ("cuaw", "cưa"), ("muaw", "mưa"), ("hoawcj", "hoặc"),
        ("cangw", "căng"), ("quawng", "quăng"), ("vieejt", "việt"), ("tieesng", "tiếng"),
        ("tiseeng", "tiếng"), ("tooi", "tôi"), ("yeeu", "yêu"), ("nguowif", "người"),
        ("hocj", "học"), ("truowngf", "trường"), ("phowr", "phở"), ("ddepj", "đẹp"),
        ("nuowcs", "nước"), ("mootj", "một"), ("beef", "bề"), ("bees", "bế"),
    ])
    func vietnameseWordIdenticalWithFlagOnAndOff(raw: String, expected: String) {
        let on = EngineConfig(literalAfterCancel: true)
        let off = EngineConfig(literalAfterCancel: false)
        #expect(typeThroughEngine(raw + " ", config: on) == expected + " ")
        #expect(typeThroughEngine(raw + " ", config: off) == expected + " ")
    }
}
