// EngineTogglesTests.swift — TDD suite for Phase 4's three Telex-side
// toggles: quick start-consonant (f→ph, j→gi, w→qu), quick end-consonant
// (g→ng, h→nh, k→ch), and sentence auto-capitalize. All three default OFF
// (dormant) — see DECISIONS.md "Quick consonants & auto-capitalize".
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

// MARK: - Quick start-consonant (f→ph, j→gi, w→qu), onset only

@Suite("QuickStartConsonant")
struct QuickStartConsonantTests {
    private let on = EngineConfig(quickStartConsonant: true)
    private let off = EngineConfig(quickStartConsonant: false)

    @Test func fExpandsToPhAtWordStart() {
        #expect(typeThroughEngine("fa ", config: on) == "pha ")
    }

    @Test func jExpandsToGiAtWordStart() {
        #expect(typeThroughEngine("ja ", config: on) == "gia ")
    }

    @Test func wExpandsToQuAtWordStart() {
        #expect(typeThroughEngine("wa ", config: on) == "qua ")
    }

    @Test func capitalKeyKeepsClusterNaturallyCased() {
        #expect(typeThroughEngine("Fa ", config: on) == "Pha ")
    }

    @Test func midWordFStillMeansHuyenTone() {
        // Only the word's very FIRST keystroke shortcuts — f/j/w reaching the
        // fold after cells already exist keep their ordinary tone/horn duty.
        #expect(typeThroughEngine("af ", config: on) == "à ")
    }

    @Test func offKeepsTodaysBehavior() {
        #expect(typeThroughEngine("fa ", config: off) == "fa ")
        #expect(typeThroughEngine("ja ", config: off) == "ja ")
        // "w" is already a live Telex key off this feature (bare w -> ư,
        // design spec Part A §2) — unrelated to quickStartConsonant, and
        // unchanged by it being off.
        #expect(typeThroughEngine("wa ", config: off) == "ưa ")
    }
}

// MARK: - Quick end-consonant (g→ng, h→nh, k→ch), coda only

@Suite("QuickEndConsonant")
struct QuickEndConsonantTests {
    // restoreIfInvalid is off here to isolate the per-key coda expansion
    // (Telex.fold) from the separate whole-word phonotactic-validity restore
    // layer — see DECISIONS.md. E.g. "bak"→"bach" is a well-formed shape at
    // the onset/nucleus/coda level, but a *ngang*-toned "bach" is rejected by
    // Phonology's stop-coda tone restriction (§5.4: p/t/c/ch codas require
    // sắc/nặng); with restoreIfInvalid ON that word would revert to raw keys
    // at commit, same as any other stop-coda word typed without a sắc/nặng
    // tone (this mirrors the already-documented restore-if-invalid split).
    private let on = EngineConfig(restoreIfInvalid: false, quickEndConsonant: true)
    private let off = EngineConfig(restoreIfInvalid: false, quickEndConsonant: false)

    @Test func gExpandsToNgAfterVowel() {
        #expect(typeThroughEngine("tog ", config: on) == "tong ")
    }

    @Test func hExpandsToNhAfterVowel() {
        #expect(typeThroughEngine("vih ", config: on) == "vinh ")
    }

    @Test func kExpandsToChAfterVowel() {
        #expect(typeThroughEngine("bak ", config: on) == "bach ")
    }

    @Test func ordinaryWordWithGAfterConsonantIsUnaffected() {
        // Critical safety case: the coda-closing "g" in "tong" (t-o-n-g)
        // follows "n", not a vowel, so it must NOT expand to "tonng".
        #expect(typeThroughEngine("tong ", config: on) == "tong ")
    }

    @Test func toneKeyInterleavesWithEndShortcut() {
        // The "s" tone key applies to the "o" nucleus; the trailing "g" still
        // sees a vowel immediately before it and expands to "ng".
        #expect(typeThroughEngine("tosg ", config: on) == "tóng ")
    }

    @Test func offRestoresPlainG() {
        #expect(typeThroughEngine("tog ", config: off) == "tog ")
    }
}

// MARK: - Sentence auto-capitalize (commit-time, reuses atSentenceStart)

@Suite("AutoCapitalize")
struct AutoCapitalizeTests {
    private let on = EngineConfig(autoCapitalize: true)
    private let off = EngineConfig(autoCapitalize: false)

    @Test func freshEngineCapitalizesFirstWord() {
        #expect(typeThroughEngine("hoa ", config: on) == "Hoa ")
    }

    @Test func englishWordCapitalizesViaRestoreBranch() {
        // "hello" isn't a legal Vietnamese syllable, so restoreIfInvalid
        // (on by default) reverts it to raw keystrokes — capitalization must
        // still apply there.
        #expect(typeThroughEngine("hello ", config: on) == "Hello ")
    }

    @Test func alreadyCapitalFirstLetterIsLeftAlone() {
        #expect(typeThroughEngine("Hoa ", config: on) == "Hoa ")
    }

    @Test func onlySentenceInitialWordCapitalizes() {
        // After a terminator ('.') the next word capitalizes; a mid-sentence
        // word (no terminator before it) does not.
        #expect(typeThroughEngine("hoa. lan ", config: on) == "Hoa. Lan ")
    }

    @Test func offLeavesCasingAlone() {
        #expect(typeThroughEngine("hoa ", config: off) == "hoa ")
    }
}

// MARK: - Sentence auto-capitalize after Return/KeypadEnter (commitNewline)

/// Replay literal keys AND explicit Enter presses through a fresh `Engine`,
/// reconstructing the on-screen text. `typeThroughEngine` above only calls
/// `engine.process`, so it can't inject a Return — this helper hands the
/// caller the engine directly so steps can call `engine.flushNewline()` too.
private func typeWithEnter(_ config: EngineConfig, _ steps: (Engine, (EngineResult) -> Void) -> Void) -> String {
    let engine = Engine(config: config)
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    steps(engine, apply)
    return String(String.UnicodeScalarView(acc))
}

@Suite("AutoCapitalizeAfterNewline")
struct AutoCapitalizeAfterNewlineTests {
    @Test func newlineStartsNewSentence() {
        let config = EngineConfig(autoCapitalize: true)
        let result = typeWithEnter(config) { engine, apply in
            for ch in "hoa " { apply(engine.process(KeyInput(ch))) }   // fresh start -> "Hoa "
            for ch in "lan " { apply(engine.process(KeyInput(ch))) }   // mid-sentence -> "lan "
            apply(engine.flushNewline())                                // Enter -> new sentence
            for ch in "mai " { apply(engine.process(KeyInput(ch))) }   // sentence-initial -> "Mai "
        }
        #expect(result == "Hoa lan Mai ")
    }

    @Test func dashBulletAtLineStartCapitalizes() {
        let config = EngineConfig(autoCapitalize: true)
        let result = typeWithEnter(config) { engine, apply in
            apply(engine.flushNewline())   // Enter on a fresh engine: sets atSentenceStart, commits nothing
            for ch in "- muc " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "- Muc ")
    }

    @Test func newlineWithAutoCapitalizeOffLeavesLowercase() {
        let config = EngineConfig(autoCapitalize: false)
        let result = typeWithEnter(config) { engine, apply in
            for ch in "hoa " { apply(engine.process(KeyInput(ch))) }
            for ch in "lan " { apply(engine.process(KeyInput(ch))) }
            apply(engine.flushNewline())
            for ch in "mai " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "hoa lan mai ")
    }
}

// MARK: - Auto-capitalize: a terminator needs trailing whitespace
//
// `Engine.updateSentenceStart` used to treat ANY "." "!" "?" as starting a
// new sentence, even when a word character (or digit) followed immediately
// with no whitespace — so "readme.md" wrongly capitalized the "md", and "cat
// readme.m" + Tab gave "cat readme.M". Fixed by the tri-state
// `SentencePosition` (see `SentencePositionTests.swift` and DECISIONS.md
// "Auto-capitalize: dấu kết câu phải có khoảng trắng theo sau"): a
// terminator only starts a sentence once whitespace confirms it; a letter or
// digit glued onto it cancels it instead; any other punctuation (including
// markdown closers `* _ \` ~`) is transparent. Tests below are in three
// groups: the bug fix itself, side effects of the fix that are intentional
// (behavior that changed on purpose, not a bug), and regression guards on
// behavior that already worked before the fix and must keep working.
@Suite("AutoCapitalizeTerminatorNeedsWhitespace")
struct AutoCapitalizeTerminatorNeedsWhitespaceTests {
    private let on = EngineConfig(autoCapitalize: true)

    /// English-mode counterpart of `typeThroughEngine`: type `keys`, then a
    /// trailing `flushInactive()` (a Tab). See `typeInactiveWithReset` below.
    private func typeInactiveEngine(_ keys: String, config: EngineConfig) -> String {
        typeInactiveWithReset(config) { engine, type, apply in
            type(keys)
            apply(engine.flushInactive())
        }
    }

    // -- Bug fix: a terminator glued to a word/digit no longer starts a sentence --

    @Test func terminatorGluedToWordCharDoesNotCapitalizeMidDocument() {
        // Exact repro from the bug report: "cat readme.m" then Tab, typed
        // mid-sentence (a fresh engine reset to simulate a real session,
        // not the fresh-engine sentence-initial case the other tests use).
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()   // mid-sentence, like a real session
            for ch in "cat readme.m" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "cat readme.m")
    }

    @Test func terminatorGluedToWordCharDoesNotCapitalize_googleDotCom() {
        #expect(typeThroughEngine("google.com ", config: on) == "Google.com ")
    }

    @Test func terminatorGluedToWordCharDoesNotCapitalize_objDotMethod() {
        #expect(typeThroughEngine("obj.method(", config: on) == "Obj.method(")
    }

    @Test func terminatorGluedToDigitDoesNotCapitalize() {
        // Telex digits are boundary chars (not word chars) — same "glued, no
        // whitespace" rule must apply to them too.
        #expect(typeThroughEngine("hoa.5 lan ", config: on) == "Hoa.5 lan ")
    }

    @Test func vietnameseModeMacroGluedToTerminatorDoesNotCapitalize() {
        let cfg = EngineConfig(macrosEnabled: true,
                                macros: [MacroRule(trigger: "vn", replacement: "việt nam", autoCapitalize: true)])
        #expect(typeThroughEngine("hoa.vn ", config: cfg) == "hoa.việt nam ")
    }

    @Test func englishModeMacroGluedToTerminatorDoesNotCapitalize() {
        let cfg = EngineConfig(macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
                                macros: [MacroRule(trigger: "md", replacement: "markdown",
                                                    expandInEnglishMode: true, autoCapitalize: true)])
        #expect(typeInactiveEngine("readme.md", config: cfg) == "readme.markdown")
    }

    @Test func vniTerminatorGluedToWordCharDoesNotCapitalize() {
        let vni = EngineConfig(inputMethod: .vni, autoCapitalize: true)
        #expect(typeThroughEngine("google.com ", config: vni) == "Google.com ")
    }

    // -- Deliberate behavior changes --

    @Test func terminatorWithNoWordComposingNowCounts() {
        // Deliberate side effect of the fix: a terminator typed with NO word
        // composing (right after a digit, or after a bare space) now feeds
        // sentence tracking too, via `process`'s rawKeys-empty early return —
        // English mode already behaved this way.
        #expect(typeThroughEngine("nawm 2020. tieeps ", config: on) == "Năm 2020. Tiếp ")
        #expect(typeThroughEngine("hoa . lan ", config: on) == "Hoa . Lan ")
    }

    @Test func tabAfterATerminatorDoesNotConfirmIt() {
        // Tab/arrows/Escape carry no character of their own (`nil` boundary
        // to `SentencePosition.after`), so — deliberately, conservatively —
        // they neither confirm nor cancel a pending terminator: a wrong
        // capital from a stray Tab (focus change, shell completion, indent)
        // is worse than a missed one.
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "hoa." { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())   // models Tab: nothing composing, no character
            for ch in "lan " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "hoa.lan ")
    }

    @Test func terminatorGluedToAWordRightAfterANewlineCancelsIt() {
        // A terminator opens the same "maybe sentence end" window even with
        // nothing composing (right after `flushNewline`) — a word gluing
        // onto it cancels the start exactly like mid-sentence ("readme.md"),
        // so "...vaf " stays "...và ", not "...Và ".
        let result = typeWithEnter(on) { engine, apply in
            apply(engine.flushNewline())
            for ch in "...vaf " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "...và ")
    }

    // -- Regression guards: unchanged from before the fix --

    @Test func terminatorFollowedBySpaceStillCapitalizes() {
        #expect(typeThroughEngine("xin chaof. banj ", config: on) == "Xin chào. Bạn ")
    }

    @Test func multiCharTerminatorsFollowedBySpaceStillCapitalize() {
        #expect(typeThroughEngine("hoa?! lan ", config: on) == "Hoa?! Lan ")
        #expect(typeThroughEngine("hoa... lan ", config: on) == "Hoa... Lan ")
    }

    @Test func closingPunctuationStaysTransparent() {
        #expect(typeThroughEngine("hoa.\" lan ", config: on) == "Hoa.\" Lan ")
        #expect(typeThroughEngine("(hoa.) lan ", config: on) == "(Hoa.) Lan ")
    }

    // A markdown closer between the terminator and the confirming space must
    // stay transparent, or "**chú ý.** tiếp" would wrongly stay lowercase
    // past the "**" instead of capitalizing "Tiếp".
    @Test func markdownBoldCloserStaysTransparentOnAPendingTerminator() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "**chus ys.** tieeps " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "**chú ý.** Tiếp ")
    }

    @Test func markdownItalicCloserStaysTransparentOnAPendingTerminator() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "_hoa._ lan " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "_hoa._ Lan ")
    }

    @Test func vietnameseModeMacroWithWhitespaceStillCapitalizes() {
        let cfg = EngineConfig(macrosEnabled: true,
                                macros: [MacroRule(trigger: "vn", replacement: "việt nam", autoCapitalize: true)])
        #expect(typeThroughEngine("hoa. vn ", config: cfg) == "hoa. Việt nam ")
    }

    @Test func englishModeMacroWithWhitespaceStillCapitalizes() {
        let cfg = EngineConfig(macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
                                macros: [MacroRule(trigger: "md", replacement: "markdown",
                                                    expandInEnglishMode: true, autoCapitalize: true)])
        #expect(typeInactiveEngine("readme. md", config: cfg) == "readme. Markdown")
    }

    @Test func resetCancelsAPendingTerminator() {
        // `Engine.reset()` (mouse click / app switch / Cmd-Ctrl-Option chord) has no actual
        // information that the next word starts a sentence, so it clears a
        // pending terminator along with the raw-key buffer.
        let result = typeWithEnter(on) { engine, apply in
            for ch in "hoa." { apply(engine.process(KeyInput(ch))) }   // fresh engine -> "Hoa."
            engine.reset()
            for ch in " lan " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "Hoa. lan ")
    }

    @Test func vniTerminatorFollowedBySpaceStillCapitalizes() {
        let vni = EngineConfig(inputMethod: .vni, autoCapitalize: true)
        #expect(typeThroughEngine("xin chao2. ban5 ", config: vni) == "Xin chào. Bạn ")
    }
}

// MARK: - English mode: resetInactive() must clear sentence tracking too

/// Replay literal keys through a fresh `Engine`'s `processInactive`, handing
/// the caller the engine so steps can call `resetInactive()`/`flushInactive()`
/// mid-stream — the English-mode counterpart of `typeWithEnter`. Mirrors
/// EngineControllerTests' `typeInactive`: every English-mode key physically
/// passes through, so `type` applies the returned edit FIRST, then appends
/// the physical key; `flushInactive()` has no physical key, so callers apply
/// its result via `apply`.
private func typeInactiveWithReset(
    _ config: EngineConfig, _ steps: (Engine, (String) -> Void, (EngineResult) -> Void) -> Void
) -> String {
    let engine = Engine(config: config)
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    func type(_ keys: String) {
        for ch in keys {
            apply(engine.processInactive(KeyInput(ch)))
            acc.append(contentsOf: String(ch).unicodeScalars)   // physical passthrough key
        }
    }
    steps(engine, type, apply)
    return String(String.UnicodeScalarView(acc))
}

// `Engine.resetInactive()` (English mode; fired by Cmd/Ctrl/Option chords
// such as Cmd+V or Option+←) used to only clear the raw-key buffer, leaving `sentencePosition` untouched — so a
// pending "." or a fresh engine's initial sentence start survived a reset and
// still capitalized the next macro, unlike Vietnamese mode's `reset()`, which
// already clears it. See DECISIONS.md "Auto-capitalize: resetInactive() cũng
// xoá vị trí đầu câu".
@Suite("EnglishModeResetClearsSentenceStart")
struct EnglishModeResetClearsSentenceStartTests {
    private let cfg = EngineConfig(
        macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
        macros: [MacroRule(trigger: "md", replacement: "markdown",
                            expandInEnglishMode: true, autoCapitalize: true)])

    @Test func pendingTerminatorDoesNotSurviveResetInactive() {
        // Bug: a reset key right after "hoa." left the pending "." in place,
        // so " md" still capitalized as if whitespace had confirmed it.
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("hoa.")
            engine.resetInactive()
            type(" md")
            apply(engine.flushInactive())
        }
        #expect(result == "hoa. markdown")
    }

    @Test func sentenceStartDoesNotSurviveResetInactiveEither() {
        // Same bug on a fresh engine: its initial `.sentenceStart` (there
        // only to capitalize a session's very first word) survived a reset
        // with nothing typed yet — same fix as `reset()` for Vietnamese mode.
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            engine.resetInactive()
            type("md")
            apply(engine.flushInactive())
        }
        #expect(result == "markdown")
    }

    @Test func noResetStillCapitalizesAfterATerminator() {
        // Guard: unaffected by the fix — whitespace after "." still confirms
        // the sentence start normally when there is no reset in between.
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("hoa. md")
            apply(engine.flushInactive())
        }
        #expect(result == "hoa. Markdown")
    }
}

// MARK: - Quick end-consonant under the DEFAULT restoreIfInvalid (real usage)

@Suite("QuickEndConsonantRealistic")
struct QuickEndConsonantRealisticTests {
    // How users actually run it: restoreIfInvalid stays ON (its default). The
    // isolated suite above turns it off to test the raw expansion; here we
    // prove the whole path (expansion + phonotactic validity) works.
    private let on = EngineConfig(quickEndConsonant: true)

    @Test func ngAndNhCodasSurviveUntoned() {
        // ng / nh are not stop codas, so ngang is legal and the expanded word
        // passes the whole-word validity check.
        #expect(typeThroughEngine("tog ", config: on) == "tong ")
        #expect(typeThroughEngine("vih ", config: on) == "vinh ")
    }

    @Test func kToChIsUsableEndToEndWithATone() {
        // k→ch closes a stop coda (needs sắc/nặng). With the nặng key "j" the
        // expanded "bạch" is valid and survives — proving k→ch is usable in
        // real typing, not only with restoreIfInvalid off.
        #expect(typeThroughEngine("bakj ", config: on) == "bạch ")
    }

    @Test func untonedStopCodaCorrectlyRestores() {
        // A bare "bak": the ngang "bach" isn't a real word (stop coda needs a
        // tone), so restore-if-invalid reverts to the raw keys — correct.
        #expect(typeThroughEngine("bak ", config: on) == "bak ")
    }
}

// MARK: - Regression guard: all new flags default OFF

@Suite("NewTogglesDormantByDefault")
struct NewTogglesDormantByDefaultTests {
    @Test func ordinaryWordsRenderUnchangedWithDefaultConfig() {
        let config = EngineConfig()
        #expect(typeThroughEngine("tieengs ", config: config) == "tiếng ")
        #expect(typeThroughEngine("vieejt ", config: config) == "việt ")
    }
}
