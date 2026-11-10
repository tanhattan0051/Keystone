// LexiconRealDictionaryTests.swift — end-to-end suite driven through the
// REAL system word list (`LexiconLoader.load()`, i.e.
// `/usr/share/dict/words` merged with `SupplementaryWords`), not a hermetic
// hand-picked one — the closest thing to what actually ships. Skips
// gracefully (not a failure) when that file isn't present on the machine
// running the suite (see DECISIONS.md "Restore chooses the composed word
// when it is the real one").

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine
import Foundation


// `letter`/`RETURN`/`typeAndFlush`/`applyRealistically` are shared with
// EngineControllerTests.swift and LexiconRestoreTests.swift — see
// RealisticTyping.swift.

@Suite(
    "LexiconRealDictionary",
    .enabled(if: systemDictExists, "requires /usr/share/dict/words, not present on this machine")
)
struct LexiconRealDictionaryTests {
    // Loaded once per suite run (not once per test) would be nicer, but
    // `LexiconLoader.load()` is cheap enough (single pass, see item 5) and
    // this keeps every test independent/order-agnostic.
    private var realLexicon: Lexicon { LexiconLoader.load() }

    @Test func realLexiconHasItsPrefixIndexBuilt() {
        let lexicon = realLexicon
        #expect(lexicon.isPrefixIndexBuilt)
        #expect(lexicon.isPrefix("suspen"))
    }

    // MARK: - The nine-row cancel-habit table, against the real dictionary.

    @Test func tassk_wantsTask() {
        #expect(typeAndFlush("tassk", lexicon: realLexicon) == "task")
    }
    @Test func gooogle_wantsGoogle() {
        #expect(typeAndFlush("gooogle", lexicon: realLexicon) == "google")
    }
    @Test func fixx_wantsFix() {
        #expect(typeAndFlush("fixx", lexicon: realLexicon) == "fix")
    }
    @Test func classss_wantsClass() {
        #expect(typeAndFlush("classss", lexicon: realLexicon) == "class")
    }
    @Test func passss_wantsPass() {
        #expect(typeAndFlush("passss", lexicon: realLexicon) == "pass")
    }
    @Test func missss_wantsMiss() {
        #expect(typeAndFlush("missss", lexicon: realLexicon) == "miss")
    }
    @Test func pressss_wantsPress() {
        #expect(typeAndFlush("pressss", lexicon: realLexicon) == "press")
    }
    @Test func lessss_wantsLess() {
        #expect(typeAndFlush("lessss", lexicon: realLexicon) == "less")
    }
    @Test func offff_wantsOff() {
        #expect(typeAndFlush("offff", lexicon: realLexicon) == "off")
    }

    // MARK: - vietnix, typed with a cancel, against the real dictionary.

    @Test func vietnixx_wantsVietnix() {
        #expect(typeAndFlush("vietnixx", lexicon: realLexicon) == "vietnix")
    }

    // MARK: - Every false-positive word the exhaustive search found commits
    // unchanged (raw) — `protectedRealWords` must keep each one recognized.

    private static let falsePositiveWords: [String] = [
        "fussed", "mussed", "mussing", "jarred", "purred", "parring", "riffling",
        "coiffed", "squirreling", "moussing", "suss", "terra", "torr", "barre",
        "lassi", "frisson", "farro", "barrie", "currie", "buffo", "triffid",
        "transsonic", "hassidic", "hassidim", "chassidim", "mycorrhiza", "degass",
        "unbiassed", "poisson", "cassava", "cassaba", "hassan",
        "parramatta", "kerr", "starr", "neff", "foxx",
    ]

    @Test(arguments: falsePositiveWords)
    func falsePositiveWordCommitsUnchanged(_ w: String) {
        #expect(typeAndFlush(w, lexicon: realLexicon) == w, "natural typing of \(w)")
    }

    // Natural `aaa` (a,a,a) commits `aa`: the screen already shows "aa" (the third
    // a undid the circumflex), so Space must not jump back to three letters. This
    // matches OpenKey; the literal AAA is typed a,a,a,a. See DECISIONS.md
    // "The aaa/eee/ooo escape in raw-restore".
    @Test func naturalAaaCommitsAa() {
        #expect(typeAndFlush("aaa", lexicon: realLexicon) == "aa")
        #expect(typeAndFlush("aaaa", lexicon: realLexicon) == "aaa")
    }

    // MARK: - The aaa/eee/ooo circumflex escape, through the shipped path
    // (EngineController + real lexicon + cancel rule ON). Natural words with the
    // V-C-V-V shape (exceed, cocoon, esteem) must commit exactly as main does;
    // only a literal a,a,a / e,e,e / o,o,o run is the escape. Expected values were
    // checked against a `git archive HEAD` copy: main commits each word as typed,
    // except IEEE, which main commits as IEEE and this change as IEE (the screen
    // already shows IEE; the literal is typed I,E,E,E,E).
    @Test(arguments: ["esteem", "exceed", "exceeds", "veneer", "cocoon", "monsoon",
                      "mongoose", "tepee", "beseech", "Canaan", "nocookie"])
    func naturalVcvvWordsCommitAsMainDoes(_ w: String) {
        #expect(typeAndFlush(w, config: Self.cancelRuleOn, lexicon: realLexicon) == w)
    }
    @Test func ieeeCommitsWhatTheScreenShows() {
        #expect(typeAndFlush("IEEE", config: Self.cancelRuleOn, lexicon: realLexicon) == "IEE")
    }
    @Test(arguments: [("aaapenl", "aapenl"), ("aaapanel", "aapanel"),
                      ("eeexit", "eexit"), ("ooops", "oops")])
    func literalEscapeRunDropsTheCircumflexKey(_ typed: String, _ want: String) {
        let c = EngineController(config: Self.cancelRuleOn)
        c.setLexicon(realLexicon)
        var acc: [Unicode.Scalar] = []
        for ch in typed {
            applyRealistically(c.handle(letter(ch)), to: &acc)
            #expect(!String(String.UnicodeScalarView(acc)).hasPrefix("aaa"))
        }
        applyRealistically(c.handle(RETURN), to: &acc)
        #expect(String(String.UnicodeScalarView(acc)) == want)
    }
    @Test func backspaceAfterTheEscapeThenAgainCommitsAa() {
        let c = EngineController(config: Self.cancelRuleOn)
        c.setLexicon(realLexicon)
        var acc: [Unicode.Scalar] = []
        for k in [letter("a"), letter("a"), letter("a"), BACKSPACE, letter("a"), RETURN] {
            applyRealistically(c.handle(k), to: &acc)
        }
        #expect(String(String.UnicodeScalarView(acc)) == "aa")   // main: "aaa"
    }

    // MARK: - Natural identifiers and names, with the cancel rule ON.
    //
    // The rule is only live with `literalAfterCancel` (every test above uses the default
    // config, where it is off). These five were measured on main d0d3837 against this same
    // lexicon: all commit exactly as typed, and the rule alone (without its two guards:
    // exactly one key vanished, no mixed case) turned them into `boundEror`, `iString`,
    // `adducces`, `OString` and `Monterat`. Found by the final review on 46.6M tokens of code
    // and man pages the acceptance corpus did not contain.
    private static let cancelRuleOn = EngineConfig(
        inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
        freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)

    private static let identifiersAndNames: [String] = [
        "boundsError", "isString", "addSuccess", "OSString", "Montserrat",
    ]

    @Test(arguments: identifiersAndNames)
    func identifierOrNameCommitsAsTypedWithTheCancelRuleOn(_ w: String) {
        #expect(typeAndFlush(w, config: Self.cancelRuleOn, lexicon: realLexicon) == w,
                "natural typing of \(w)")
    }

    // MARK: - Habit-typed sysadmin words.
    //
    // The author types `sy` + `s` and sees `sý`; the second `s` cancels the tone. The lexicon
    // (`SupplementaryWords.all`) knows these words, so the composed spelling wins by rule 2.
    // Natural `systems` and habit `sysstems` must both commit `systems`: the dictionary has no
    // word that starts with `sysst`, so the raw spelling is not English-like (a protected word
    // `sysstat` would make it one and break habit `systems`/`systemd`, see DECISIONS.md).
    private static let habitSysadminWords: [(typed: String, committed: String)] = [
        ("syssadmin", "sysadmin"), ("syssctl", "sysctl"), ("syssfs", "sysfs"),
        ("syssinfo", "sysinfo"), ("syssprep", "sysprep"), ("sysstemd", "systemd"),
        ("sysstemctl", "systemctl"), ("sysstems", "systems"), ("systems", "systems"),
    ]

    @Test(arguments: habitSysadminWords)
    func habitTypedSysadminWordCommitsWithoutTheCancelKey(_ word: (typed: String, committed: String)) {
        #expect(typeAndFlush(word.typed, config: Self.cancelRuleOn, lexicon: realLexicon) == word.committed,
                "habit typing of \(word.committed)")
    }

    // The residue the two guards cannot remove: a morpheme-boundary double in a code word
    // (`insstr`, curses; `sysstat`, the sysadmin tool), an ALL-CAPS constant (`OSSTRING`), a
    // foreign proper noun (`Alessandro`) and a real word the 1934 list lacks (`sassiness`,
    // `misscanned`, `misscanning`) look, at the keystroke level, exactly like a habit-typed
    // `instr` / `systat` / `OSTRING` / `Alesandro` / `sasiness`; only the dictionary could tell
    // them apart and it does not know them. Each loses exactly ONE letter (the guard admits a
    // word only when a single key vanished, so a second letter cannot be lost). `sysstat` and
    // the other three are NOT protected on purpose: a protected entry becomes a dictionary
    // PREFIX and breaks habit typing of common words (`systems` -> `sysstems`), see DECISIONS.md.
    // This pins what is COMMITTED today, as a documented limitation and not an endorsement: a
    // change to the margin or the guards moves it, and then this test must be updated on
    // purpose, with the numbers re-measured. DECISIONS.md "Cancel keeps the literal" has the
    // measured size of the residue.
    private static let acceptedResidue: [(typed: String, committed: String)] = [
        ("insstr", "instr"), ("Alessandro", "Alesandro"), ("OSSTRING", "OSTRING"),
        ("sysstat", "systat"), ("sassiness", "sasiness"),
        ("misscanned", "miscanned"), ("misscanning", "miscanning"),
    ]

    @Test(arguments: acceptedResidue)
    func acceptedResidueStillLosesOneLetter(_ residue: (typed: String, committed: String)) {
        #expect(typeAndFlush(residue.typed, config: Self.cancelRuleOn, lexicon: realLexicon)
                == residue.committed, "natural typing of \(residue.typed)")
    }

    // MARK: - Quick-consonant words commit raw with the relevant toggle, even
    // against the real (much bigger) dictionary — the subsequence guard, not
    // dictionary luck, is what protects these.

    private static let quickConsonantCases: [(word: String, config: EngineConfig)] = [
        ("sinning", EngineConfig(quickTelex: true)),
        ("patted", EngineConfig(quickTelex: true)),
        ("scatting", EngineConfig(quickTelex: true)),
        ("jt", EngineConfig(quickStartConsonant: true)),
        ("wilted", EngineConfig(quickTelex: true)),
        ("wilted", EngineConfig(quickStartConsonant: true)),
        ("wilted", EngineConfig(quickEndConsonant: true)),
        ("wilting", EngineConfig(quickTelex: true)),
        ("wilting", EngineConfig(quickStartConsonant: true)),
        ("wilting", EngineConfig(quickEndConsonant: true)),
        ("wadded", EngineConfig(quickTelex: true)),
        ("wadded", EngineConfig(quickStartConsonant: true)),
        ("wadded", EngineConfig(quickEndConsonant: true)),
        ("foto", EngineConfig(quickStartConsonant: true)),
        ("raged", EngineConfig(quickEndConsonant: true)),
        ("nike", EngineConfig(quickEndConsonant: true)),
        ("gaga", EngineConfig(quickEndConsonant: true)),
        ("tek", EngineConfig(quickEndConsonant: true)),
        ("likened", EngineConfig(quickEndConsonant: true)),
        ("luged", EngineConfig(quickEndConsonant: true)),
        ("bak", EngineConfig(quickEndConsonant: true)),
        ("muk", EngineConfig(quickEndConsonant: true)),
        ("lok", EngineConfig(quickEndConsonant: true)),
        ("pihole", EngineConfig(quickEndConsonant: true)),
        ("ik", EngineConfig(quickEndConsonant: true)),
        ("gaging", EngineConfig(quickEndConsonant: true)),
        ("welch", EngineConfig(quickTelex: true)),
        ("welch", EngineConfig(quickStartConsonant: true)),
        ("welch", EngineConfig(quickEndConsonant: true)),
        ("pitt", EngineConfig(quickTelex: true)),
    ]

    @Test func quickConsonantWordsCommitRaw() {
        for (word, config) in Self.quickConsonantCases {
            #expect(typeAndFlush(word, config: config, lexicon: realLexicon) == word,
                     "\(word) under \(config)")
        }
    }

    // MARK: - Broad natural-typing list commits unchanged.
    //
    // "room" and "door" are deliberately EXCLUDED here, not overlooked: both
    // fold into a phonologically-VALID Vietnamese syllable before restore
    // ever gets a say — "room" -> oo is the Telex ô key -> "rôm"; "door" ->
    // oo -> ô, then trailing "r" is the Telex hỏi-tone key, not a literal
    // coda -> "dổ". `restoreIfInvalid`'s `!isValid(comp)` guard is false for
    // both, so `Engine.finalize` never reaches the lexicon/RestoreDecision
    // branch at all — confirmed reproducible with `lexicon: nil` (HEAD,
    // pre-lexicon behavior), so this is a separate, pre-existing Telex
    // phonological-validity gap, not something this feature could fix or
    // regress. See `LexiconKnownIssuesTests` below, and this task's report.

    private static let naturalTypingWords: [String] = [
        "coffee", "hello", "letter", "success", "access", "address", "message", "glass",
        "grass", "boss", "kiss", "dress", "stress", "express", "possible", "assist",
        "essay", "issue", "across", "stuff", "staff", "office", "effort", "offer",
        "different", "error", "mirror", "sorry", "carry", "worry", "arrow", "tomorrow",
        "free", "agree", "need", "good", "food", "book", "school", "add",
        "odd", "passing", "missing",
    ]

    @Test(arguments: naturalTypingWords)
    func naturalTypingWordCommitsUnchanged(_ w: String) {
        #expect(typeAndFlush(w, lexicon: realLexicon) == w, "natural typing of \(w)")
    }
}

@Suite(
    "LexiconKnownIssues",
    .enabled(if: systemDictExists, "requires /usr/share/dict/words, not present on this machine")
)
struct LexiconKnownIssuesTests {
    private var realLexicon: Lexicon { LexiconLoader.load() }

    /// Documents (rather than hides) the "room"/"door" finding above as a
    /// known issue: `withKnownIssue` keeps the suite green while still
    /// failing loudly if these ever start passing unexpectedly (signaling
    /// the underlying Telex phonological-validity gap was fixed) or if a
    /// change here ever makes them fail a DIFFERENT way.
    @Test func roomAndDoorFoldToAValidVietnameseSyllableBeforeRestoreEverRuns() {
        withKnownIssue("pre-existing, unrelated to the lexicon feature: 'oo'/'r' are Telex diacritic keys, so \"room\"/\"door\" are phonologically-valid Vietnamese syllables and never reach RestoreDecision — reproduces with lexicon: nil too") {
            #expect(typeAndFlush("room", lexicon: realLexicon) == "room")
            #expect(typeAndFlush("door", lexicon: realLexicon) == "door")
        }
    }
}
