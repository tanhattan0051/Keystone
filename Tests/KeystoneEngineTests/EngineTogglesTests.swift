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
    }

    @Test func terminatorReachedAfterWhitespaceIsUnconfirmable() {
        // Glue-aware follow-up (see DECISIONS.md): a "." reached right after
        // whitespace was NEVER glued to real text, so — unlike the
        // "hoa. lan" case above — it can never become a sentence start, no
        // matter how much whitespace follows it. This is the base/OpenKey
        // behavior; it replaces this fix's own former "Hoa . Lan" pin (see
        // "Auto-capitalize: dấu kết câu phải có khoảng trắng theo sau" in
        // DECISIONS.md).
        #expect(typeThroughEngine("hoa . lan ", config: on) == "Hoa . lan ")
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
// such as Cmd+V or Option+←) used to only clear the raw-key buffer, leaving
// `sentencePosition` untouched — so a pending "." or a fresh engine's
// initial sentence start survived a reset and still capitalized the next
// macro, unlike Vietnamese mode's `reset()`, which already clears it. See
// DECISIONS.md "Auto-capitalize: resetInactive() cũng xoá vị trí đầu câu".
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

// MARK: - Glue-aware follow-up: RESET must still assume TEXT precedes the
// caret (`.afterReset`, `gluedToText: true`), not `.midSentence` — see
// DECISIONS.md "Auto-capitalize: dấu kết câu phải có khoảng trắng theo sau"
// decision A. Regression found replaying identical keystrokes against
// e50c3ad and against base (English mode): a terminator typed right after a
// reset (mouse click, app/keyboard-focus switch, a Cmd/Ctrl/Option chord, or
// Vietnamese off→on) could never confirm any more, because `reset()`/
// `resetInactive()` cleared the glue along with everything else — even
// though the engine genuinely has no idea whether real text (pasted text,
// pre-existing text, a word typed while Vietnamese was off) sits right
// before the caret. The next WORD right after a reset still does NOT
// capitalize on its own — only a terminator reaching a confirming
// whitespace after the reset does.
@Suite("AutoCapitalizeResetAssumesTextBeforeCaret")
struct AutoCapitalizeResetAssumesTextBeforeCaretTests {
    private let on = EngineConfig(autoCapitalize: true)

    @Test func terminatorReachedRightAfterAResetCanStillConfirm() {
        let result = typeWithEnter(on) { engine, apply in
            for ch in "hoa" { apply(engine.process(KeyInput(ch))) }
            engine.reset()   // mouse click / app switch / Cmd-Ctrl-Option chord
            for ch in ". lan " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "hoa. Lan ")
    }

    @Test func exclamationReachedRightAfterAResetCanStillConfirm() {
        let result = typeWithEnter(on) { engine, apply in
            for ch in "hoa" { apply(engine.process(KeyInput(ch))) }
            engine.reset()
            for ch in "! lan " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "hoa! Lan ")
    }

    @Test func vniTerminatorReachedRightAfterAResetCanStillConfirm() {
        let vni = EngineConfig(inputMethod: .vni, autoCapitalize: true)
        let result = typeWithEnter(vni) { engine, apply in
            for ch in "hoa" { apply(engine.process(KeyInput(ch))) }
            engine.reset()
            for ch in ". lan " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "hoa. Lan ")
    }

    @Test func setActiveStyleResetLeavesAConfirmableWindowAfterInvisibleText() {
        // Models `EngineController.setActive(false)` (-> `engine.reset()`)
        // -> text typed while Vietnamese is off, a passthrough the pure
        // `Engine` never sees at all (modeled here as a hand-built
        // `EngineResult` applied directly to the accumulator, exactly like
        // the real physical passthrough) -> `setActive(true)` (does NOT
        // reset) -> resumed Vietnamese typing. Repro: "tooi dungf " +
        // setActive(false) + [Docker, invisible] + setActive(true) +
        // ". nos raats" → "tôi dùng Docker. nó rất" without this fix
        // (should be "Nó").
        let result = typeWithEnter(on) { engine, apply in
            for ch in "tooi dungf " { apply(engine.process(KeyInput(ch))) }
            engine.reset()
            apply(EngineResult(backspaceCount: 0, text: "Docker"))
            for ch in ". nos raats" { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "Tôi dùng Docker. Nó rất")
    }

    @Test func englishModeTerminatorReachedRightAfterAResetInactiveCanStillConfirm() {
        let cfg = EngineConfig(
            macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
            macros: [MacroRule(trigger: "md", replacement: "markdown",
                                expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("hello")
            engine.resetInactive()
            type(". md")
            apply(engine.flushInactive())
        }
        #expect(result == "hello. Markdown")
    }

    @Test func resetRightAfterATrailingSpaceWronglyLetsTheNextTerminatorConfirm() {
        // Accepted consequence of `.afterReset`'s conservative `gluedToText:
        // true` — see DECISIONS.md. A reset landing right after WHITESPACE
        // (not text) is indistinguishable, to `Engine`, from one landing
        // right after text, so the terminator right after this reset
        // WRONGLY confirms — unlike continuous typing with no reset in
        // between, where "hoa . lan " stays lowercase "lan"
        // (`terminatorReachedAfterWhitespaceIsUnconfirmable`).
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()   // mid-session, like a real session — avoids the
                              // fresh-engine first-word capital muddying the comparison
            for ch in "hoa " { apply(engine.process(KeyInput(ch))) }
            engine.reset()   // lands right after the trailing space, not text
            for ch in ". lan " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "hoa . Lan ")
    }
}

// MARK: - Glue-aware follow-up: operators/editorial-asides must NOT open a
// confirmable window, a Telex digit glued to a pending terminator must
// cancel back to `settled` (not always `.midSentence`), a CLOSER (R2b below)
// must force glue back on so a terminator right after it CAN open a fresh
// confirmable window, and there is no dedicated "=" rule any more (R1b
// below) — "=" is just ordinary transparent punctuation, which is enough on
// its own once glue-awareness exists — see DECISIONS.md "Auto-capitalize:
// dấu kết câu phải có khoảng trắng theo sau". Regressions found replaying
// identical keystrokes against the terminator-needs-whitespace fix above,
// and against e50c3ad/base for R2b/R1b: a terminator NOT glued to text
// (typed after whitespace or an opening bracket) still opened the window;
// cancelling a pending terminator always went to `.midSentence` instead of
// back to the position the terminator interrupted; a closer being fully
// transparent left an aside's terminator unconfirmable forever even after
// the aside visibly ended; and the old "=" rule cancelled a pending
// terminator on sight, swallowing Vietnamese chat emoticons like "!=))".
@Suite("AutoCapitalizeOperatorsAndEditorialAsides")
struct AutoCapitalizeOperatorsAndEditorialAsidesTests {
    private let on = EngineConfig(autoCapitalize: true)

    // -- R1: operators with spaces must not read as sentence terminators --

    @Test func inequalityOperatorInACodeLineDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()   // mid-session, like a real editor buffer
            for ch in "while (i != n) {" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "while (i != n) {")
    }

    @Test func ternaryOperatorDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "x = a ? b : c" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "x = a ? b : c")
    }

    @Test func nullCoalescingOperatorDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "let y = x ?? fallback" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "let y = x ?? fallback")
    }

    @Test func strictInequalityOperatorDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "check (a !== undefined) return" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "check (a !== undefined) return")
    }

    @Test func inequalityOperatorGluedOnBothSidesDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "a!=b" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "a!=b")
    }

    @Test func asymmetricSpacingAfterAnOperatorCapitalizesAcceptedLimitation() {
        // Accepted limitation (see DECISIONS.md): there is no dedicated "="
        // rule any more (deleted — glue-awareness makes it unnecessary for
        // the symmetric/glued cases below), so a terminator glued to a word
        // on ONE side but followed by whitespace on the other ("a!= b",
        // "a?= b") is indistinguishable from a real "word. Word" sentence
        // end — the "!"/"?" IS glued to real text ("a"), and the "=" that
        // follows is ordinary transparent punctuation, so the whitespace
        // after it confirms the window same as any other terminator would.
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "a!= b" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "a!= B")

        let result2 = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "a?= b" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result2 == "a?= B")
    }

    @Test func inequalityOperatorDoesNotCapitalizeACapitalizingMacro() {
        let cfg = EngineConfig(macrosEnabled: true,
                                macros: [MacroRule(trigger: "ko", replacement: "không", autoCapitalize: true)])
        let result = typeWithEnter(cfg) { engine, apply in
            engine.reset()
            for ch in "x != ko " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "x != không ")
    }

    // -- R2: an editorial aside/spaced ellipsis must not open a confirmable window --

    @Test func parenthesizedExclamationInTheMiddleOfASentenceDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "gias 5 tyr (!) cho mootj cawn" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "giá 5 tỷ (!) cho một căn")
    }

    @Test func parenthesizedQuestionMarkInTheMiddleOfASentenceDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "anh ta (?) ddeens" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "anh ta (?) đến")
    }

    @Test func parenthesizedEllipsisInTheMiddleOfASentenceDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "trawm nawm (...) nhuwngx" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "trăm năm (...) những")
    }

    @Test func spacedEllipsisNotInParensDoesNotCapitalize() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "tooi nghix ... roofi thooi" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "tôi nghĩ ... rồi thôi")
    }

    // -- R2b: a CLOSER right after an aside forces glue back on, so a
    // terminator reached right after IT can open a fresh confirmable window
    // (regression found replaying against e50c3ad: closers used to be fully
    // transparent, so the terminator inside the aside stayed
    // unconfirmable forever) --

    @Test func terminatorRightAfterAClosingParenCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "gias 5 tyr (!). sau ddos" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "giá 5 tỷ (!). Sau đó")
    }

    @Test func terminatorRightAfterAClosingParenWithATwoCharTerminatorRunCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "anh ta (?!). sau ddos" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "anh ta (?!). Sau đó")
    }

    @Test func terminatorRightAfterAClosingParenInsideAnEmoticonCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "ddepj quas :). mai" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "đẹp quá :). Mai")
    }

    @Test func terminatorRightAfterADoubleClosingParenEmoticonCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "vui quas =)). mai" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "vui quá =)). Mai")
    }

    @Test func terminatorRightAfterAClosingParenMidSentenceStillCapitalizesWithLeadingContext() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "anh aays nois rawngf (...). sau ddos" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "anh ấy nói rằng (...). Sau đó")
    }

    @Test func closerWithNoTerminatorAfterItStillDoesNotCapitalize() {
        // Regression guard: the closer fix must not, by itself, start
        // capitalizing text that never had a confirmed terminator after it —
        // this must keep failing to capitalize "cho" exactly as before.
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "gias 5 tyr (!) cho" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "giá 5 tỷ (!) cho")
    }

    @Test func aConfirmablePendingOpenedBeforeAParenIsUnaffectedByTheCloser() {
        // Regression guard: unchanged from before the closer fix — a pending
        // terminator opened BEFORE the bracket (glued to real text) is left
        // exactly alone by the closer, not resurrected or re-judged.
        #expect(typeThroughEngine("(hoa.) lan ", config: on) == "(Hoa.) Lan ")
    }

    // -- R1b: without a dedicated "=" rule, an emoticon terminator glued
    // directly to a WORD (not reached after whitespace/an opener) still
    // opens a confirmable window exactly like any other glued terminator —
    // "=" itself is just ordinary transparent punctuation in between --

    @Test func exclamationGluedToAWordBeforeAnEqualsEmoticonCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "vui quas!=)) mai gawpj" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "vui quá!=)) Mai gặp")
    }

    @Test func questionMarkGluedToAWordBeforeAnEqualsEmoticonCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "thaatj har?=)) uwf" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "thật hả?=)) Ừ")
    }

    @Test func periodGluedToAWordBeforeAnEqualsEmoticonCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "vui quas.=)) mai" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "vui quá.=)) Mai")
    }

    @Test func exclamationGluedToAWordBeforeASingleClosingParenEmoticonCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "camr own!=) heenj" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "cảm ơn!=) Hện")
    }
}

// MARK: - Accepted limitations: a terminator right after a PUNCTUATION-ONLY
// token that itself follows whitespace never confirms, even once that token
// visibly ends — missed capitals, same in base 6ba2ab7 and e50c3ad (not new
// to this fix; conservative by design). The "(" of an unmatched ":(" and an
// opening `"` both make `gluedToText` false exactly like whitespace would,
// and — for the quote case — the closing `"` never gets the CLOSER
// treatment `)`/`"` get, so nothing re-sets the glue before the "." is
// reached. See DECISIONS.md "Accepted limitations". Contrast with
// `AutoCapitalizeOperatorsAndEditorialAsidesTests`'s R2b pins above
// (":). Mai", "=)). Mai"), which DO capitalize because those emoticons end
// in a real closer.
@Suite("AutoCapitalizeAcceptedLimitationsPunctuationOnlyToken")
struct AutoCapitalizeAcceptedLimitationsPunctuationOnlyTokenTests {
    private let on = EngineConfig(autoCapitalize: true)

    @Test func sadFaceEmoticonWithNoClosingParenNeverConfirms() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()   // mid-session — avoid the fresh-engine first-word capital
            for ch in "buoonf quas :((. mai gawpj" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "buồn quá :((. mai gặp")
    }

    @Test func caretEmoticonNeverConfirms() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "vui quas ^^. mai" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "vui quá ^^. mai")
    }

    @Test func shrugEmoticonNeverConfirms() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "vui quas -_-. mai" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "vui quá -_-. mai")
    }

    @Test func atSignEmoticonNeverConfirms() {
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "vui quas @@. mai" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "vui quá @@. mai")
    }

    @Test func quotedPunctuationOnlyTokenNeverConfirms() {
        // "...", quoted, is itself just the terminator — the closing
        // straight quote right before it stays fully transparent (it is
        // NOT a closer), so the "." never gets a fresh confirmable window.
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "anh nois \"...\". sau ddos" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "anh nói \"...\". sau đó")
    }

    @Test func englishModePunctuationOnlyEmoticonBeforeAMacroNeverConfirms() {
        let cfg = EngineConfig(macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
                                macros: [MacroRule(trigger: "md", replacement: "markdown",
                                                    expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            engine.resetInactive()
            type("so sad :((. md")
            apply(engine.flushInactive())
        }
        #expect(result == "so sad :((. markdown")
    }
}

// MARK: - Glue-aware follow-up: R3, Telex numbered headings/dates at line
// start must keep the capital a `flushNewline` sentence start already
// earned, even though the glued digit cancels the pending "." — see
// DECISIONS.md "Auto-capitalize: dấu kết câu phải có khoảng trắng theo sau".
@Suite("AutoCapitalizeLineStartNumberedHeadings")
struct AutoCapitalizeLineStartNumberedHeadingsTests {
    private let on = EngineConfig(autoCapitalize: true)

    @Test func numberedSubheadingAfterNewlineCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            apply(engine.flushNewline())
            for ch in "1.1 giowis thieeuj" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "1.1 Giới thiệu")
    }

    @Test func dottedDateAfterNewlineCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            apply(engine.flushNewline())
            for ch in "24.09 hopj" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "24.09 Họp")
    }

    @Test func multiLevelNumberedHeadingAfterNewlineCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            apply(engine.flushNewline())
            for ch in "2.3.1 keets quar" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "2.3.1 Kết quả")
    }

    @Test func bareNumberAtASentenceStartStillCapitalizesTheFollowingWord() {
        // Unchanged, documented limitation: telling a line-start numbered
        // heading apart from a bare number mid-sentence would need more
        // than "is a digit typed after this terminator", so both keep the
        // capital ("3 Lan" and "3.14 Lan" below).
        #expect(typeThroughEngine("hoa. 3 lan ", config: on) == "Hoa. 3 Lan ")
    }

    @Test func parenthesizedNumberAfterNewlineCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            apply(engine.flushNewline())
            for ch in "1) lan " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "1) Lan ")
    }

    @Test func decimalNumberAfterATerminatorStillCapitalizesTheFollowingWord() {
        // Consistent with `bareNumberAtASentenceStartStillCapitalizesTheFollowingWord`
        // above: the "." inside "3.14" opens its own window, glued digits
        // cancel it, but `settled` (inherited from "hoa."'s confirmed
        // sentence start) survives every cancel.
        #expect(typeThroughEngine("hoa. 3.14 lan ", config: on) == "Hoa. 3.14 Lan ")
    }

    @Test func vniDecimalNumberAfterATerminatorStaysLowercaseUnlikeTelex() {
        // Telex-ONLY claim (see DECISIONS.md): in VNI (and English mode)
        // digits are word chars (`isWordChar`), so "3.14" reaches
        // `SentencePosition` via the COMMITTED-WORD path — which
        // unconditionally collapses to `.midSentence` — never the "cancel
        // back to `settled`" path a bare Telex digit BOUNDARY char takes.
        // Unchanged in ALL versions (base, e50c3ad, and this fix).
        let vni = EngineConfig(inputMethod: .vni, autoCapitalize: true)
        #expect(typeThroughEngine("hoa. 3.14 lan ", config: vni) == "Hoa. 3.14 lan ")
    }

    @Test func abbreviationLikeTerminatorStillCapitalizesMidSession() {
        // Accepted limitation (unchanged): telling "e.g." apart from a real
        // sentence end would need a dictionary — see DECISIONS.md.
        let result = typeWithEnter(on) { engine, apply in
            engine.reset()
            for ch in "e.g. x " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "e.g. X ")
    }
}

// MARK: - Glue-aware follow-up: a unit glued STRAIGHT onto a line-start
// digit (no whitespace between them) is a continuation of that same token,
// not a sentence-initial word of its own — pre-existing false capital, same
// in base 6ba2ab7 and e50c3ad (VNI already right, since VNI digits are word
// chars and never take this boundary-char path at all — see
// `vniDecimalNumberAfterATerminatorStaysLowercaseUnlikeTelex` above). Fixed
// by `SentencePosition.isSentenceStart`'s `!gluedToText` — see its doc
// comment and DECISIONS.md "Auto-capitalize: dấu kết câu phải có khoảng
// trắng theo sau".
@Suite("AutoCapitalizeUnitGluedToNumberAtSentenceStart")
struct AutoCapitalizeUnitGluedToNumberAtSentenceStartTests {
    private let on = EngineConfig(autoCapitalize: true)

    @Test func unitLetterGluedToADigitRightAfterATerminatorStaysLowercase() {
        // Was "Xin chào. 3H chiều nay " — the "h" of "3h" is glued straight
        // onto the "3", so it must not read as sentence-initial just because
        // `settled` survived the digit's cancel of the pending ".".
        #expect(typeThroughEngine("xin chaof. 3h chieeuf nay ", config: on) == "Xin chào. 3h chiều nay ")
    }

    @Test func unitLetterGluedToADigitRightAfterANewlineStaysLowercase() {
        // Was "10H sáng " — same bug, this time the digit inherits
        // `settled == .sentenceStart` from `flushNewline` instead of a
        // confirmed terminator.
        let result = typeWithEnter(on) { engine, apply in
            apply(engine.flushNewline())
            for ch in "10h sangs " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "10h sáng ")
    }

    @Test func unitLetterGluedToADigitMidSentenceAfterATerminatorStaysLowercase() {
        // Was "Hoa. 5Kg gạo " — glued unit right after the confirmed "hoa."
        // sentence start.
        #expect(typeThroughEngine("hoa. 5kg gaoj ", config: on) == "Hoa. 5kg gạo ")
    }

    @Test func ordinalSuffixGluedToADigitRightAfterANewlineStaysLowercase() {
        // Was "2Nd place " — an ordinal suffix ("2nd") is exactly the same
        // "glued unit" shape as "3h"/"10h"/"5kg".
        let result = typeWithEnter(on) { engine, apply in
            apply(engine.flushNewline())
            for ch in "2nd place " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "2nd place ")
    }

    // -- Regression guards: unaffected by the `!gluedToText` fix, since a
    // SPACE (not a glued unit) separates the digit from the next word --

    @Test func bareNumberFollowedBySpaceStillCapitalizesTheNextWord() {
        #expect(typeThroughEngine("hoa. 3 lan ", config: on) == "Hoa. 3 Lan ")
    }

    @Test func numberedSubheadingAfterNewlineStillCapitalizes() {
        let result = typeWithEnter(on) { engine, apply in
            apply(engine.flushNewline())
            for ch in "1.1 giowis thieeuj" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flush())
        }
        #expect(result == "1.1 Giới thiệu")
    }
}

// MARK: - Test gaps found by mutation testing: each of these must fail if
// the line it names is broken.
@Suite("AutoCapitalizeMutationCoveragePins")
struct AutoCapitalizeMutationCoveragePinsTests {
    // (a) English-mode Return: `flushInactiveNewline` must call
    // `matchEnglishMacro` BEFORE forcing `sentencePosition = .sentenceStart`
    // (finalize-before-set order) — the macro's own `atSentenceStart` read
    // must see the state as it was BEFORE Return's "new sentence" news.
    @Test func englishModeReturnCommitsANonMacroWordBeforeStartingTheNextSentence() {
        let cfg = EngineConfig(
            macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
            macros: [MacroRule(trigger: "md", replacement: "markdown",
                                expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("hello")
            apply(engine.flushInactiveNewline())
            type(" md")
            apply(engine.flushInactive())
        }
        #expect(result == "hello Markdown")
    }

    @Test func englishModeReturnStartsANewSentenceForTheMacroRightAfterIt() {
        let cfg = EngineConfig(
            macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
            macros: [MacroRule(trigger: "md", replacement: "markdown",
                                expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("md")
            apply(engine.flushInactiveNewline())
            type("md")
            apply(engine.flushInactive())
        }
        #expect(result == "MarkdownMarkdown")
    }

    // (b) Return while a word is still composing: `flushNewline` must
    // finalize the pending word (judged against the OLD sentence position)
    // BEFORE forcing the new sentence start, so only the word AFTER Return
    // capitalizes.
    @Test func returnWhileAWordIsComposingCommitsItBeforeStartingTheNextSentence() {
        let result = typeWithEnter(EngineConfig(autoCapitalize: true)) { engine, apply in
            for ch in "hoa lan" { apply(engine.process(KeyInput(ch))) }
            apply(engine.flushNewline())
            for ch in "mai " { apply(engine.process(KeyInput(ch))) }
        }
        #expect(result == "Hoa lanMai ")
    }

    // (c) A macro commit must cancel a pending terminator exactly like an
    // ordinary word commit does (both read the same `hadWord`/`committedWord`).
    @Test func repeatedCapitalizingMacroOnlyCapitalizesAtASentenceStart() {
        let cfg = EngineConfig(macrosEnabled: true,
                                macros: [MacroRule(trigger: "vn", replacement: "việt nam", autoCapitalize: true)])
        #expect(typeThroughEngine("vn vn ", config: cfg) == "Việt nam việt nam ")
    }

    @Test func macroGluedToATerminatorCancelsItLikeAnOrdinaryWordCommit() {
        let cfg = EngineConfig(macrosEnabled: true,
                                macros: [MacroRule(trigger: "vn", replacement: "việt nam", autoCapitalize: true)])
        #expect(typeThroughEngine("hoa.vn vn ", config: cfg) == "hoa.việt nam việt nam ")
    }

    // (d) English-mode word commit (no macro match) must feed
    // `updateSentenceStart` with `hadWord: true` exactly like a Vietnamese-
    // mode commit does.
    @Test func englishModeMacroFiresAgainAfterAnOrdinaryWordCommit() {
        let cfg = EngineConfig(macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
                                macros: [MacroRule(trigger: "md", replacement: "markdown",
                                                    expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("readme.md md")
            apply(engine.flushInactive())
        }
        #expect(result == "readme.markdown markdown")
    }

    // (d, gap fix) The test above doesn't actually pin `matchEnglishMacro`'s
    // NO-MATCH call site passing `hadWord: hadWord` instead of a hardcoded
    // `false` — mutation testing found it survives there, because
    // "readme.md" already collapses its OWN pending terminator via the "."
    // it contains, regardless of `hadWord`. This one starts from an already-
    // CONFIRMED sentence start ("hoa. ") so only a real `hadWord: true`
    // collapse on the "hello " commit can cancel it before "md" is judged.
    @Test func englishModeOrdinaryWordCommitCancelsAConfirmedSentenceStartBeforeTheNextMacro() {
        let cfg = EngineConfig(macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
                                macros: [MacroRule(trigger: "md", replacement: "markdown",
                                                    expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("hoa. hello md")
            apply(engine.flushInactive())
        }
        #expect(result == "hoa. hello markdown")
    }

    @Test func englishModeFlushBetweenAPendingTerminatorAndAMacroLeavesItUnconfirmed() {
        let cfg = EngineConfig(macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
                                macros: [MacroRule(trigger: "md", replacement: "markdown",
                                                    expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("hoa.")
            apply(engine.flushInactive())
            type("md")
            apply(engine.flushInactive())
        }
        #expect(result == "hoa.markdown")
    }

    // (e) `matchEnglishMacro`'s MATCH branch (a macro trigger actually
    // fires) must ALSO call `updateSentenceStart(boundary: boundary, hadWord:
    // hadWord)` on its way out — the NO-MATCH branch above (tests (a)-(d))
    // never exercises this call site at all. Deleting it, or passing
    // `boundary: nil` instead of `boundary: boundary`, both survive every
    // other test in this file.
    @Test func englishModeMacroMatchOpensAConfirmableWindowForTheNextMacro() {
        // "md." (a MATCH) is glued straight to the ".", so the MATCH
        // branch's own `updateSentenceStart` call is what has to open the
        // pending terminator — the NO-MATCH branch never sees this "."
        // at all. Deleting the MATCH-branch call, or passing `boundary:
        // nil`, both leave the pending terminator unopened, so the second
        // "md" would stay lowercase "markdown" instead of "Markdown".
        let cfg = EngineConfig(macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
                                macros: [MacroRule(trigger: "md", replacement: "markdown",
                                                    expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("I use md. md")
            apply(engine.flushInactive())
        }
        #expect(result == "I use markdown. Markdown")
    }

    @Test func englishModeMacroMatchCollapsesAConfirmedSentenceStartForTheFollowingWord() {
        // "ok." confirms a pending sentence start via the NO-MATCH branch's
        // own call (not what's under test here); by the time the first "md"
        // MATCHes, `atSentenceStart` is already true, so IT capitalizes
        // regardless. What's under test is whether that first "md" commit
        // (a MATCH) goes on to collapse the state for the SECOND "md" —
        // deleting the MATCH branch's `updateSentenceStart` call would leave
        // the confirmed sentence start standing, wrongly capitalizing the
        // second "md" too.
        let cfg = EngineConfig(macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
                                macros: [MacroRule(trigger: "md", replacement: "markdown",
                                                    expandInEnglishMode: true, autoCapitalize: true)])
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("ok. md md")
            apply(engine.flushInactive())
        }
        #expect(result == "ok. Markdown markdown")
    }
}

// MARK: - English mode, deliberate behavior changes vs BASE (before the
// whole tri-state/glue-aware fix) — see DECISIONS.md "Auto-capitalize: dấu
// kết câu phải có khoảng trắng theo sau". In VIETNAMESE mode, a terminator
// reached after whitespace/an aside/an operator never capitalized even
// under base's plain `atSentenceStart: Bool` tracker (base only ever called
// `updateSentenceStart` from inside `finalize`, which only runs when a word
// is actually composing). But base's ENGLISH-mode macro path
// (`matchEnglishMacro`) called `updateSentenceStart` unconditionally for
// EVERY boundary, composing or not — so in English mode specifically, these
// DID capitalize under base, and now (correctly) don't.
@Suite("EnglishModeGlueAwareDeliberateChanges")
struct EnglishModeGlueAwareDeliberateChangesTests {
    private let cfg = EngineConfig(
        macrosEnabled: true, macrosExpandWhenVietnameseOff: true,
        macros: [MacroRule(trigger: "md", replacement: "markdown",
                            expandInEnglishMode: true, autoCapitalize: true)])

    @Test func terminatorReachedAfterWhitespaceInEnglishModeNoLongerCapitalizes() {
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("hello . md")
            apply(engine.flushInactive())
        }
        #expect(result == "hello . markdown")
    }

    @Test func questionMarkReachedAfterWhitespaceInEnglishModeNoLongerCapitalizes() {
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("is it ok ? md")
            apply(engine.flushInactive())
        }
        #expect(result == "is it ok ? markdown")
    }

    @Test func spacedEllipsisInEnglishModeNoLongerCapitalizes() {
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("wait ... md")
            apply(engine.flushInactive())
        }
        #expect(result == "wait ... markdown")
    }

    @Test func inequalityOperatorInEnglishModeNoLongerCapitalizes() {
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("x != md")
            apply(engine.flushInactive())
        }
        #expect(result == "x != markdown")
    }

    @Test func nullCoalescingOperatorInEnglishModeNoLongerCapitalizes() {
        let result = typeInactiveWithReset(cfg) { engine, type, apply in
            type("y ?? md")
            apply(engine.flushInactive())
        }
        #expect(result == "y ?? markdown")
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
