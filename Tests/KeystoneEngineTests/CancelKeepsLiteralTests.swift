// CancelKeepsLiteralTests.swift — TDD suite for "after a Telex cancel, pick the
// more ENGLISH-LIKE spelling by dictionary prefixes", see DECISIONS.md "Cancel
// keeps the literal: English-likeness by dictionary prefixes".
//
// The habit: Tân sees a tone appear (`u n s` -> `ún`) and presses the key again
// to cancel it, so the RAW keys carry the cancel key (`unss…`). Main shows and
// commits those raw keys (`unssuspend`). The fix compares two spellings of the
// word — COMPOSED (the cancel applied: `unsuspend`) and RAW (`unssuspend`) — by
// how long each stays a prefix of some dictionary word ("depth"). The composed
// one wins only when it IS a word, or stays English-like for at least
// `englishLikenessMargin` (2) more letters than the raw one.
//
// Each engine test below uses a small hand-built `Lexicon` and says which
// words make each depth work. Rows 11-13 pin what MAIN produced (measured
// before Engine.swift changed) for the cases that must stay as they were.
//
// Same replay helpers as EagerRestoreTests.swift (file-private there).

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

/// Screen contents after EACH key of `keys` (no trailing flush).
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
private let cancelOff = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                                      freeMarkAcrossCoda: true, literalAfterCancel: false, spellCheck: true)
private let vniOn = EngineConfig(inputMethod: .vni, restoreIfInvalid: true, allowFreeToneMark: true,
                                  freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)
private let capitalizing = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, autoCapitalize: true,
                                         allowFreeToneMark: true, freeMarkAcrossCoda: true,
                                         literalAfterCancel: true, spellCheck: true)

// MARK: - The bug: a cancel key must not survive into the word

@Suite("CancelKeepsLiteralTelex")
struct CancelKeepsLiteralTelexTests {
    // "unsuspected" is the only word. Composed "unsuspend" stays a prefix for
    // 7 letters ("unsuspe"); raw "unssuspend" only for 3 ("uns"): 7 >= 3 + 2.
    private let unsuspected = Lexicon(["unsuspected"])

    @Test func row1_unssuspendCommitsWithoutTheCancelKey() {
        #expect(typeThroughEngine("unssuspend ", config: on, lexicon: unsuspected) == "unsuspend ")
    }

    @Test func row2_unssuspendNeverShowsTheCancelKeyWhileTyping() {
        let steps = typeStepwise("unssuspend", config: on, lexicon: unsuspected)
        // The 4th key is the cancelling s: the screen must show "uns", not "unss".
        #expect(steps[3] == "uns")
        #expect(steps.allSatisfy { !$0.contains("unss") })
        #expect(steps == ["u", "un", "ún", "uns", "unsu", "unsus", "unsusp", "unsuspe", "unsuspen", "unsuspend"])
    }

    // "unspent" gives composed "unspend" depth 6 ("unspen"); "unspeakable"
    // makes "unspe" a prefix twice over but adds no depth. Raw "unsspend" is 3.
    @Test func row3_unsspendCommitsWithoutTheCancelKey() {
        let lex = Lexicon(["unspent", "unspeakable"])
        #expect(typeThroughEngine("unsspend ", config: on, lexicon: lex) == "unspend ")
    }

    // "suspend" is itself the composed word (rule: composed is in the lexicon).
    @Test func row4_susspendCommitsAndNeverShowsTheCancelKey() {
        let lex = Lexicon(["suspend"])
        #expect(typeThroughEngine("susspend ", config: on, lexicon: lex) == "suspend ")
        #expect(typeStepwise("susspend", config: on, lexicon: lex)
                == ["s", "su", "sú", "sus", "susp", "suspe", "suspen", "suspend"])
    }

    @Test func row5_tasskCommitsAsTask() {
        let lex = Lexicon(["task"])
        #expect(typeThroughEngine("tassk ", config: on, lexicon: lex) == "task ")
        #expect(typeStepwise("tassk", config: on, lexicon: lex) == ["t", "ta", "tá", "tas", "task"])
    }

    // "class" is a word: natural "class" keeps the raw spelling (the raw keys
    // ARE the word), and "classs" (an extra cancel) gives the composed word
    // "class". "clasp" only has to be there so "clas" is a prefix.
    //
    // At the cancelling key the raw keys "class" are themselves the word, so the
    // display shows them. The next key kills the raw spelling ("classs" is no
    // prefix) exactly one key after the cancel, which is the habit-cancel
    // signature, so the composed "class" may take over at once (the early rule of
    // `chooseMidWordAfterCancel`).
    @Test func row6_classAndClassssBothCommitClass() {
        let lex = Lexicon(["class", "clasp"])
        #expect(typeThroughEngine("class ", config: on, lexicon: lex) == "class ")
        #expect(typeThroughEngine("classs ", config: on, lexicon: lex) == "class ")
        #expect(typeStepwise("class", config: on, lexicon: lex).last == "class")
        #expect(typeStepwise("classs", config: on, lexicon: lex).last == "class")
    }

    @Test func row7_messsageAndMessageBothCommitMessage() {
        let lex = Lexicon(["message"])
        #expect(typeThroughEngine("message ", config: on, lexicon: lex) == "message ")
        #expect(typeThroughEngine("messsage ", config: on, lexicon: lex) == "message ")
    }

    // The word the first attempt broke: "messages" is NOT in the 1934 lexicon,
    // only "message" is. Raw "messages" stays a prefix for 7 letters, composed
    // "mesages" for 3: the composed form is nowhere near 2 letters better.
    @Test func row8_naturalMessagesStaysMessages() {
        let lex = Lexicon(["message"])
        #expect(typeThroughEngine("messages ", config: on, lexicon: lex) == "messages ")
        #expect(typeStepwise("messages", config: on, lexicon: lex).last == "messages")
    }

    // Raw "processing" stays a prefix for 8 letters ("processi" via
    // "procession"), composed "procesing" for 6; raw "diff" 4 ("difference")
    // vs composed "dif" 3. The raw spelling is at least as English-like.
    @Test func row9_naturalProcessingAndDiffAreUnchanged() {
        let lex = Lexicon(["process", "procession", "difference"])
        #expect(typeThroughEngine("processing ", config: on, lexicon: lex) == "processing ")
        #expect(typeThroughEngine("diff ", config: on, lexicon: lex) == "diff ")
    }

    // The margin-1 regression: composed "oneror" has depth 5 ("onero" via
    // "onerous"), raw "onerror" has depth 4 ("oner"). One letter of
    // difference is not enough, which is why the margin is 2, not 1.
    @Test func row10_naturalOnerrorStaysOnerror() {
        let lex = Lexicon(["onerous", "error"])
        #expect(typeThroughEngine("onerror ", config: on, lexicon: lex) == "onerror ")
    }

    // Row 14: capitalization is applied to whichever spelling wins.
    @Test func row14_sentenceStartCapitalizesTheComposedWinner() {
        #expect(typeThroughEngine("unssuspend ", config: capitalizing, lexicon: unsuspected) == "Unsuspend ")
    }

    @Test func uppercaseKeysAreComparedLowercased() {
        #expect(typeThroughEngine("UNSSUSPEND ", config: on, lexicon: unsuspected) == "UNSUSPEND ")
    }
}

// MARK: - Cases that must stay exactly as main had them (rows 11-13)

@Suite("CancelKeepsLiteralUnchangedFromMain")
struct CancelKeepsLiteralUnchangedFromMainTests {
    private let unsuspected = Lexicon(["unsuspected"])

    // Row 11 — VNI. The cancel key is a DIGIT and digits are ordinary text
    // (`win11`, `ubuntu22.04`): the rule must not eat one. The lexicon holds
    // words that START with the composed form ("a1x" -> "a1", "win1x" ->
    // "win1", "ubuntu2x" -> "ubuntu2"), so that if the VNI gate were missing
    // the mid-word rule would show the composed form (composed is a prefix, raw
    // is not). They are not equal to it: that would also move MAIN's own
    // `choose`. Strings pinned from main d0d3837.
    @Test func row11_vniDoubledDigitsAreDataNotCancels() {
        let lex = Lexicon(["a1x", "win1x", "ubuntu2x"])
        #expect(typeThroughEngine("a11 ", config: vniOn, lexicon: lex) == "a11 ")
        #expect(typeThroughEngine("win11 ", config: vniOn, lexicon: lex) == "win11 ")
        #expect(typeThroughEngine("ubuntu22.04 ", config: vniOn, lexicon: lex) == "ubuntu22.04 ")
        #expect(typeStepwise("a11", config: vniOn, lexicon: lex) == ["a", "á", "a11"])
        #expect(typeStepwise("win11", config: vniOn, lexicon: lex) == ["w", "wi", "win", "win1", "win11"])
    }

    // Row 12 — each switch that makes the rule dormant. Strings pinned from main.
    @Test func row12_literalAfterCancelOffIsMain() {
        #expect(typeThroughEngine("unssuspend ", config: cancelOff, lexicon: unsuspected) == "unssuspend ")
        #expect(typeStepwise("unssuspend", config: cancelOff, lexicon: unsuspected)
                == ["u", "un", "ún", "unss", "unssu", "unssus", "unssusp", "unssuspe", "unssuspen", "unssuspend"])
    }

    @Test func row12_nilLexiconIsMain() {
        #expect(typeThroughEngine("unssuspend ", config: on, lexicon: nil) == "unssuspend ")
        #expect(typeStepwise("unssuspend", config: on, lexicon: nil)
                == ["u", "un", "ún", "unss", "unssu", "unssus", "unssusp", "unssuspe", "unssuspen", "unssuspend"])
    }

    @Test func row12_unbuiltPrefixIndexIsMain() {
        // A lexicon someone inserted into after construction: stale index.
        var stale = Lexicon(["unsuspected"])
        stale.insert("zzz")
        #expect(!stale.isPrefixIndexBuilt)
        #expect(typeThroughEngine("unssuspend ", config: on, lexicon: stale) == "unssuspend ")
        #expect(typeStepwise("unssuspend", config: on, lexicon: stale)
                == ["u", "un", "ún", "unss", "unssu", "unssus", "unssusp", "unssuspe", "unssuspen", "unssuspend"])
    }

    @Test func row12_unbuiltPrefixIndexKeepsMainsEagerRawRender() {
        // Main shows the raw cancel key while typing and commits the composed
        // word only because "suspend" is a real one. An unbuilt index must not
        // change either half (not even to the better-looking trace).
        var stale = Lexicon()
        stale.insert("suspend")
        #expect(!stale.isPrefixIndexBuilt)
        #expect(typeStepwise("susspend", config: on, lexicon: stale)
                == ["s", "su", "sú", "suss", "sussp", "susspe", "susspen", "susspend"])
        #expect(typeThroughEngine("susspend ", config: on, lexicon: stale) == "suspend ")
    }

    // The gate's tone condition: a cancel of ANOTHER mark (`ooo` undoes the
    // circumflex) while the sắc from `s` survives. The word is still a
    // Vietnamese attempt (`taóo`), so the existing restore keeps it. The lexicon
    // holds the composed "taóo" so a missing tone gate would show (main's own
    // `choose` rejects it: it is not a subsequence of the raw keys). Pinned
    // from main.
    @Test func aCancelThatLeavesAToneIsMain() {
        let lex = Lexicon(["ta\u{00F3}o"])
        #expect(typeThroughEngine("tasooo ", config: on, lexicon: lex) == "tasooo ")
        #expect(typeStepwise("tasooo", config: on, lexicon: lex)
                == ["t", "ta", "tá", "táo", "taố", "taóo"])
    }

    // The index gate itself (not only "depth is 0 without an index"). The lexicon holds
    // ONLY "arowweed", the composed spelling of `arrowweed` (rr cancels, then w w are
    // literal). Main refuses it: the ww-collapsed raw `arroweed` has one w, so the composed
    // word is not a subsequence of it. The new rule's guard is looser (it also tries the
    // keys as typed, which do contain both w's), so with a BUILT index it would pick the
    // composed word; with a stale index the gate must hand the decision back to main.
    // Pinned from main.
    @Test func row12_unbuiltPrefixIndexDefersToMainsStricterChoice() {
        var stale = Lexicon()
        stale.insert("arowweed")
        #expect(!stale.isPrefixIndexBuilt)
        #expect(typeThroughEngine("arrowweed ", config: on, lexicon: stale) == "arroweed ")
        // Contrast: the same word list, indexed, is decided by the new rule.
        #expect(typeThroughEngine("arrowweed ", config: on, lexicon: Lexicon(["arowweed"])) == "arowweed ")
    }

    // Row 13 — the cancel leaves a circumflex on `ê` (`viêt`), so the cancelled
    // literal does not apply. The lexicon holds "viêt" (NFC) so a missing
    // vowel-mark gate would show. Strings pinned from main.
    @Test func row13_cancelThatLeavesACircumflexIsMain() {
        let lex = Lexicon(["vi\u{00EA}t"])
        #expect(typeThroughEngine("vieetss ", config: on, lexicon: lex) == "vieetss ")
        #expect(typeStepwise("vieetss", config: on, lexicon: lex)
                == ["v", "vi", "vie", "viê", "viêt", "viết", "vieetss"])
    }
}

// MARK: - The subsequence guard, through the engine (quick consonants)

@Suite("CancelKeepsLiteralQuickConsonants")
struct CancelKeepsLiteralQuickConsonantsTests {
    // A quick-consonant toggle can put letters in the composed word that the user never
    // typed (f -> ph, k -> ch, cc -> ch). If such a word is also cancelled and the composed
    // spelling happens to be listed, the cancel rule must NOT commit it: composed has to be
    // obtainable from the raw keys by deleting characters only, the same refusal main's
    // `choose` makes. Each lexicon lists exactly the expanded spelling, so without the guard
    // both the mid-word display and the commit would pick it. Strings pinned from main.
    private func config(start: Bool = false, end: Bool = false, quick: Bool = false) -> EngineConfig {
        EngineConfig(inputMethod: .telex, restoreIfInvalid: true, quickTelex: quick,
                     quickStartConsonant: start, quickEndConsonant: end, allowFreeToneMark: true,
                     freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)
    }

    @Test func quickStartConsonantExpansionIsNotCommittedOverTheRawKeys() {
        // f -> ph at the start; ss cancels the sắc. Composed "phons".
        let lex = Lexicon(["phons"])
        let c = config(start: true)
        #expect(typeThroughEngine("fonss ", config: c, lexicon: lex) == "fonss ")
        #expect(typeStepwise("fonss", config: c, lexicon: lex) == ["ph", "pho", "phon", "phón", "fonss"])
    }

    @Test func quickEndConsonantExpansionIsNotCommittedOverTheRawKeys() {
        // k after a vowel -> ch; ss cancels the sắc. Composed "achs".
        let lex = Lexicon(["achs"])
        let c = config(end: true)
        #expect(typeThroughEngine("akss ", config: c, lexicon: lex) == "akss ")
        #expect(typeStepwise("akss", config: c, lexicon: lex) == ["a", "ach", "ách", "akss"])
    }

    @Test func quickTelexExpansionIsNotCommittedOverTheRawKeys() {
        // cc -> ch; ss cancels the sắc. Composed "chas".
        let lex = Lexicon(["chas"])
        let c = config(quick: true)
        #expect(typeThroughEngine("ccass ", config: c, lexicon: lex) == "ccass ")
        #expect(typeStepwise("ccass", config: c, lexicon: lex) == ["c", "ch", "cha", "chá", "ccass"])
    }

    @Test func theCancelRuleStillWorksWithAQuickToggleOnWhenNothingWasExpanded() {
        // Same toggles on, but no key is expanded: the guard must let a normal cancel through.
        let lex = Lexicon(["unsuspected"])
        let c = config(start: true, end: true, quick: true)
        #expect(typeThroughEngine("unssuspend ", config: c, lexicon: lex) == "unsuspend ")
    }
}


// MARK: - RestoreDecision.chooseAfterCancel, pure

@Suite("ChooseAfterCancel")
struct ChooseAfterCancelTests {
    // One word, so every depth is easy to read off: "abcdefg".
    private let lex = Lexicon(["abcdefg"])

    // Every composed/raw pair below satisfies the subsequence guard (composed is raw with some
    // characters deleted, exactly what a cancel does), so the rule under test is the one named.
    // A raw is built by inserting a stray letter X into the composed spelling: the earlier the
    // X, the shallower the raw's depth. For composed "abcdexx" (depth 5):
    //   "abcdXexx" -> depth 4 (difference 1), "abcXdexx" -> 3 (2), "abXcdexx" -> 2 (3).

    private func commit(_ composed: String, _ raws: [String], _ lexicon: Lexicon) -> RestoreChoice {
        RestoreDecision.chooseAfterCancel(composed: composed, raws: raws, lexicon: lexicon, atCommit: true)
    }
    private func midWord(_ composed: String, _ raws: [String], _ lexicon: Lexicon) -> RestoreChoice {
        RestoreDecision.chooseAfterCancel(composed: composed, raws: raws, lexicon: lexicon, atCommit: false)
    }

    @Test func marginIsTwo() {
        #expect(RestoreDecision.englishLikenessMargin == 2)
    }

    // MARK: atCommit == true

    @Test func commitAnyRawInTheLexiconWins() {
        // Even when the composed form is a word too (contrived, but rule 1 is first).
        let l = Lexicon(["task", "tassk"])
        #expect(commit("task", ["tassk"], l) == .raw)
        // ...and any of several candidates is enough (here the second one).
        #expect(commit("abcdefg", ["abxcdefg", "tassk"], Lexicon(["abcdefg", "tassk"])) == .raw)
    }

    @Test func commitComposedInTheLexiconWins() {
        #expect(commit("abcdefg", ["abcxdefg"], lex) == .composed)
    }

    @Test func commitMarginBoundaryDepthDifferenceOneIsRawTwoIsComposed() {
        // composed "abcdexx": depth 5 ("abcde"), not a word.
        // raw "abcdXexx": depth 4 -> difference 1 -> raw.
        #expect(commit("abcdexx", ["abcdXexx"], lex) == .raw)
        // raw "abcXdexx": depth 3 -> difference 2 -> composed.
        #expect(commit("abcdexx", ["abcXdexx"], lex) == .composed)
        // difference 3 -> composed.
        #expect(commit("abcdexx", ["abXcdexx"], lex) == .composed)
    }

    @Test func commitUsesTheDeepestRaw() {
        // Two raw spellings (collapsed, as typed): depth 3 and 4 -> max 4.
        #expect(commit("abcdexx", ["abcXdexx", "abcdXexx"], lex) == .raw)
        #expect(commit("abcdexx", ["abcXdexx", "abXcdexx"], lex) == .composed)
    }

    @Test func identicalRawSpellingsDecideLikeASingleOne() {
        // With no `ww`/`ddd` the engine passes the same string twice; it is evaluated once.
        #expect(commit("abcdexx", ["abcXdexx", "abcXdexx"], lex) == commit("abcdexx", ["abcXdexx"], lex))
        #expect(commit("abcdexx", ["abcdXexx", "ABCDXEXX"], lex) == .raw)
        #expect(midWord("abcdexx", ["abcXdexx", "abcXdexx"], lex) == .composed)
    }

    @Test func commitOtherwiseRaw() {
        // Neither spelling is English-like at all.
        #expect(commit("xyz", ["xyzz"], lex) == .raw)
        // Composed no better than raw.
        #expect(commit("abcxxxx", ["abcxxxx"], lex) == .raw)
    }

    @Test func commitComparesLowercased() {
        #expect(commit("ABCDEFG", ["ABCXDEFG"], lex) == .composed)
        #expect(commit("ABCDEXX", ["ABCXDEXX"], lex) == .composed)
        // A raw that is a word wins however it is cased ("abcdfg" is a subsequence of it).
        #expect(commit("abcdfg", ["ABCDEFG"], lex) == .raw)
    }

    @Test func commitWithAnUnbuiltIndexNeverPrefersComposedByDepth() {
        var stale = Lexicon()
        stale.insert("abcdefg")
        // Depth is 0 on both sides: 0 >= 0 + 2 is false -> raw.
        #expect(commit("abcdexx", ["abcXdexx"], stale) == .raw)
    }

    // MARK: atCommit == false (mid-word display)

    @Test func midWordAnyRawPrefixWins() {
        // Raw "abcd" is a prefix: keep showing it, composed "abc" is one too.
        #expect(midWord("abc", ["abcd"], lex) == .raw)
    }

    @Test func midWordComposedPrefixWins() {
        // Composed "abc" is a prefix, raw "abcc" is not.
        #expect(midWord("abc", ["abcc"], lex) == .composed)
    }

    @Test func midWordMarginBoundary() {
        #expect(midWord("abcdexx", ["abcdXexx"], lex) == .raw)        // 5 vs 4
        #expect(midWord("abcdexx", ["abcXdexx"], lex) == .composed)   // 5 vs 3
    }

    @Test func midWordOtherwiseRaw() {
        #expect(midWord("xyz", ["xyzz"], lex) == .raw)
    }

    @Test func midWordAndCommitDifferWhereAPrefixIsNotYetAWord() {
        // Composed "abc" is a prefix but not a word, raw "abcc" is neither.
        // Mid-word that is enough (the word may still be growing); at commit it
        // is not (depth 3 < 3 + 2).
        #expect(midWord("abc", ["abcc"], lex) == .composed)
        #expect(commit("abc", ["abcc"], lex) == .raw)
    }

    @Test func midWordWithAnUnbuiltIndexIsRaw() {
        var stale = Lexicon()
        stale.insert("abcdefg")
        #expect(midWord("abc", ["abcc"], stale) == .raw)
    }

    // MARK: composedMayWinAsPrefix == false (mid-word, after the display chose RAW at the cancel key)
    //
    // The engine passes false when the cancel keystroke itself was displayed as the raw keys
    // (`miss`): the composed spelling may then replace them only on the margin rule, never
    // because it merely "is a prefix" (rule 2). Rule 1 and the subsequence guard are untouched.

    private func midWordNoPrefixFlip(_ composed: String, _ raws: [String], _ lexicon: Lexicon) -> RestoreChoice {
        RestoreDecision.chooseAfterCancel(
            composed: composed, raws: raws, lexicon: lexicon, atCommit: false, composedMayWinAsPrefix: false)
    }

    @Test func noPrefixFlipKeepsRawWhereComposedIsOnlyAPrefix() {
        // Composed "abc" is a prefix and raw "abcc" is not: rule 2 says composed ...
        #expect(midWord("abc", ["abcc"], lex) == .composed)
        // ... unless the flip is switched off. Depth 3 vs 3 is no margin.
        #expect(midWordNoPrefixFlip("abc", ["abcc"], lex) == .raw)
    }

    @Test func noPrefixFlipStillSwitchesByTheMargin() {
        #expect(midWordNoPrefixFlip("abcdexx", ["abcdXexx"], lex) == .raw)        // 5 vs 4
        #expect(midWordNoPrefixFlip("abcdexx", ["abcXdexx"], lex) == .composed)   // 5 vs 3
    }

    @Test func noPrefixFlipStillLetsARawPrefixWin() {
        #expect(midWordNoPrefixFlip("abc", ["abcd"], lex) == .raw)
    }

    @Test func noPrefixFlipStillRefusesAComposedFormThatAddsLetters() {
        // Margin 5 on depth alone, but composed is not a deletion of raw.
        #expect(midWordNoPrefixFlip("abcdexx", ["xxxxxxx"], lex) == .raw)
    }

    @Test func prefixFlipSwitchDoesNotTouchTheCommitDecision() {
        // composed is a word -> composed, with the switch either way.
        #expect(RestoreDecision.chooseAfterCancel(
            composed: "abcdefg", raws: ["abcxdefg"], lexicon: lex, atCommit: true,
            composedMayWinAsPrefix: false) == .composed)
        #expect(RestoreDecision.chooseAfterCancel(
            composed: "abc", raws: ["abcc"], lexicon: lex, atCommit: true,
            composedMayWinAsPrefix: false) == .raw)
    }

    // MARK: chooseMidWordAfterCancel (the engine's mid-word call)
    //
    // `rawShownAtCancelOfLength` is nil unless the display at the cancel keystroke was the raw
    // keys; then it is the number of keys typed up to and including that keystroke. Raw that
    // died by that position (rawDepth <= cancelLength) is the habit-cancel signature and the
    // composed spelling may win as a prefix; raw that stays alive past it is a natural word
    // and only the margin rule may switch the display.

    private func midWordAfterCancel(_ composed: String, _ raws: [String], _ lexicon: Lexicon,
                                    rawShownAtCancelOfLength n: Int?) -> RestoreChoice {
        RestoreDecision.chooseMidWordAfterCancel(
            composed: composed, raws: raws, lexicon: lexicon, rawShownAtCancelOfLength: n)
    }

    @Test func midWordWithoutARawCancelDisplayIsTheOrdinaryMidWordRule() {
        // nil: composed "abc" is a prefix, raw "abcc" is not -> composed.
        #expect(midWordAfterCancel("abc", ["abcc"], lex, rawShownAtCancelOfLength: nil) == .composed)
        #expect(midWordAfterCancel("abc", ["abcc"], lex, rawShownAtCancelOfLength: nil)
                == midWord("abc", ["abcc"], lex))
    }

    @Test func rawAliveBeyondTheCancelKeepsTheRawDisplay() {
        // raw "abcdeX" has depth 5, the cancel was 3 keys in: 5 > 3, so no prefix rule. Composed
        // "abcde" is a prefix (depth 5) but not 2 deeper than the raw one.
        #expect(midWordAfterCancel("abcde", ["abcdeX"], lex, rawShownAtCancelOfLength: 3) == .raw)
        // The very same pair with no raw cancel display would be composed.
        #expect(midWordAfterCancel("abcde", ["abcdeX"], lex, rawShownAtCancelOfLength: nil) == .composed)
    }

    @Test func rawThatDiesAtTheCancelKeyLetsTheComposedPrefixWin() {
        // raw "abcXd" has depth 3. Cancel 3 keys in: 3 <= 3 -> the prefix rule is back and
        // composed "abcd" (a prefix) wins ...
        #expect(midWordAfterCancel("abcd", ["abcXd"], lex, rawShownAtCancelOfLength: 3) == .composed)
        // ... one key earlier (cancel 2 keys in) the raw spelling outlived the cancel: raw.
        #expect(midWordAfterCancel("abcd", ["abcXd"], lex, rawShownAtCancelOfLength: 2) == .raw)
    }

    @Test func theMarginRuleStillSwitchesWhenRawIsAlive() {
        // raw "abcXdexx" depth 3, cancel 2 keys in: raw outlived it. Composed "abcdexx" depth 5
        // is 2 deeper -> composed by the margin.
        #expect(midWordAfterCancel("abcdexx", ["abcXdexx"], lex, rawShownAtCancelOfLength: 2) == .composed)
        // Depth difference 1 is no margin.
        #expect(midWordAfterCancel("abcdexx", ["abcdXexx"], lex, rawShownAtCancelOfLength: 3) == .raw)
    }

    @Test func theDeepestOfSeveralRawsDecidesTheEarlyRule() {
        // Two raw spellings (collapsed, as typed): depths 3 and 5. Cancel 3 keys in: the deepest
        // (5) is past it -> raw, although the shallow one alone would allow the prefix rule.
        #expect(midWordAfterCancel("abcde", ["abcXd", "abcdeX"], lex, rawShownAtCancelOfLength: 3) == .raw)
    }

    @Test func midWordAfterCancelStillRefusesAComposedFormThatAddsLetters() {
        #expect(midWordAfterCancel("phon", ["fonn"], Lexicon(["phone"]), rawShownAtCancelOfLength: 4) == .raw)
        #expect(midWordAfterCancel("phon", ["fonn"], Lexicon(["phone"]), rawShownAtCancelOfLength: nil) == .raw)
    }

    @Test func midWordAfterCancelWithAnUnbuiltIndexIsRaw() {
        var stale = Lexicon()
        stale.insert("abcdefg")
        #expect(midWordAfterCancel("abc", ["abcc"], stale, rawShownAtCancelOfLength: 1) == .raw)
        #expect(midWordAfterCancel("abc", ["abcc"], stale, rawShownAtCancelOfLength: nil) == .raw)
    }

    // MARK: the subsequence guard
    //
    // Composed must be obtainable from at least one raw by DELETING characters only (what a
    // cancel does). A quick-consonant toggle can instead ADD letters the user never typed
    // (f -> ph, k -> ch, cc -> ch, j -> gi, w -> qu), and main's `choose` refuses those for the
    // same reason. The guard comes first, before every other rule, in both modes.

    @Test func guardRefusesAComposedFormThatAddsLettersEvenWhenItIsAWord() {
        #expect(commit("niche", ["nike"], Lexicon(["niche"])) == .raw)       // rule 2 would say composed
        #expect(commit("phone", ["fone"], Lexicon(["phone"])) == .raw)
        #expect(commit("quilted", ["wilted"], Lexicon(["quilted"])) == .raw)
    }

    @Test func guardRefusesAComposedFormThatAddsLettersMidWord() {
        // Composed is a dictionary prefix and raw is not, so the mid-word rule 2 would say composed.
        #expect(midWord("phon", ["fonn"], Lexicon(["phone"])) == .raw)
        #expect(midWord("ach", ["ak"], Lexicon(["achs"])) == .raw)
    }

    @Test func guardAlsoBlocksTheDepthMarginRule() {
        // "abcdexx" has depth 5 and "xxxxxxx" has depth 0, a difference of 5, but composed
        // is not a deletion of raw.
        #expect(commit("abcdexx", ["xxxxxxx"], lex) == .raw)
        #expect(midWord("abcdexx", ["xxxxxxx"], lex) == .raw)
    }

    @Test func guardIsSatisfiedByAnyOneRaw() {
        // Not a deletion of the first raw, but of the second (as typed).
        #expect(commit("task", ["zzzz", "tassk"], Lexicon(["task"])) == .composed)
        #expect(midWord("tas", ["zzzz", "tass"], Lexicon(["task"])) == .composed)
    }

    @Test func guardComparesLowercased() {
        #expect(commit("TASK", ["TASSK"], Lexicon(["task"])) == .composed)
        #expect(commit("Niche", ["NIKE"], Lexicon(["niche"])) == .raw)
    }
}


// MARK: - The two guards that keep a natural word out of the cancel rule, pure

@Suite("CancelGuards")
struct CancelGuardsTests {
    // G1: a habit cancel deletes EXACTLY ONE key (raw = intended + 1).
    @Test func exactlyOneVanishedKeyPasses() {
        // unssuspend -> unsuspend: 10 keys typed, 9 letters left.
        #expect(RestoreDecision.cancelDeletedExactlyOneKey(typedCount: 10, collapsedTypedCount: 10, composedCount: 9))
    }

    @Test func moreThanOneVanishedKeyFails() {
        // boundsError -> boundEror: 11 typed, 9 left. An earlier tone key was swallowed too.
        #expect(!RestoreDecision.cancelDeletedExactlyOneKey(typedCount: 11, collapsedTypedCount: 11, composedCount: 9))
        #expect(!RestoreDecision.cancelDeletedExactlyOneKey(typedCount: 12, collapsedTypedCount: 12, composedCount: 9))
    }

    @Test func nothingVanishedFails() {
        #expect(!RestoreDecision.cancelDeletedExactlyOneKey(typedCount: 9, collapsedTypedCount: 9, composedCount: 9))
    }

    @Test func aWwEscapeCountsOnceIfTheCollapsedKeysFit() {
        // 10 typed, 9 after the ww -> w collapse, 8 composed. Raw alone says two vanished, the
        // collapsed keys say one: the second reading is enough.
        #expect(RestoreDecision.cancelDeletedExactlyOneKey(typedCount: 10, collapsedTypedCount: 9, composedCount: 8))
        // Neither reading is exactly one.
        #expect(!RestoreDecision.cancelDeletedExactlyOneKey(typedCount: 11, collapsedTypedCount: 10, composedCount: 8))
    }

    // G2M: a word that mixes lowercase with an uppercase letter after the first key is an
    // identifier or a name, never an OpenKey-habit word.
    @Test func plainCapitalizedAndAllCapsWordsDoNotMixCase() {
        #expect(!RestoreDecision.mixesLetterCase(Array("unssuspend")))
        #expect(!RestoreDecision.mixesLetterCase(Array("Unssuspend")))
        #expect(!RestoreDecision.mixesLetterCase(Array("UNSSUSPEND")))
        #expect(!RestoreDecision.mixesLetterCase(Array("A")))
        #expect(!RestoreDecision.mixesLetterCase([]))
    }

    @Test func aLaterUppercaseLetterNextToLowercaseMixesCase() {
        #expect(RestoreDecision.mixesLetterCase(Array("isString")))
        #expect(RestoreDecision.mixesLetterCase(Array("OSString")))
        #expect(RestoreDecision.mixesLetterCase(Array("boundsError")))
        #expect(RestoreDecision.mixesLetterCase(Array("McDonald")))
        #expect(RestoreDecision.mixesLetterCase(Array("iPhone")))
        #expect(RestoreDecision.mixesLetterCase(Array("aB")))
    }

    @Test func onlyTheFirstKeyMayBeUppercaseWithoutMixing() {
        // Capital first, rest lowercase: Capitalized. Capital first, rest lowercase after a later
        // capital: mixed.
        #expect(!RestoreDecision.mixesLetterCase(Array("Ab")))
        #expect(RestoreDecision.mixesLetterCase(Array("ABc")))
    }

    @Test func keysThatAreNotLettersDoNotCountAsCase() {
        #expect(!RestoreDecision.mixesLetterCase(Array("ab12")))
        #expect(!RestoreDecision.mixesLetterCase(Array("[]")))
        #expect(!RestoreDecision.mixesLetterCase(Array("a[b")))
    }
}

// MARK: - Natural identifiers and names keep their letters, through the engine
//
// The depth rule alone misreads these. Each lexicon below holds ONE word that has the
// COMPOSED spelling (the spelling after the cancel) as a proper prefix, so the composed form
// is deeper than the raw one by more than the margin and the rule alone would commit it.
// Main only prefers a composed form that IS a listed word, so it keeps the raw keys. Every
// expected string below was measured on main d0d3837 (a `git archive` copy outside the repo).

@Suite("CancelKeepsLiteralNaturalTypingStaysAsTyped")
struct CancelKeepsLiteralNaturalTypingTests {
    private func commitsAsTyped(_ word: String, lexicon words: [String]) -> Bool {
        typeThroughEngine(word + " ", config: on, lexicon: Lexicon(words)) == word + " "
    }
    private func displaysAsTyped(_ word: String, lexicon words: [String]) -> Bool {
        typeStepwise(word, config: on, lexicon: Lexicon(words)).last == word
    }

    // `boundsError`: the first `s` becomes a tone key that is swallowed, then `rr` cancels the
    // second tone. TWO letters vanish (`boundEror`): both guards reject it.
    @Test func boundsErrorKeepsEveryLetter() {
        let lex = ["bounderors"]
        #expect(commitsAsTyped("boundsError", lexicon: lex))
        #expect(displaysAsTyped("boundsError", lexicon: lex))
    }

    // `addSuccess`: `S` is swallowed as a tone key and a later `ss` cancels it: two letters
    // vanish (`adducces`) and the case is mixed.
    @Test func addSuccessKeepsEveryLetter() {
        let lex = ["adduccesx"]
        #expect(commitsAsTyped("addSuccess", lexicon: lex))
        #expect(displaysAsTyped("addSuccess", lexicon: lex))
    }

    // `isString`: the capital `S` cancels the sắc that `is` produced, so exactly ONE key
    // vanishes (`iString`). Only the mixed-case guard (G2M) can reject this one.
    @Test func isStringIsRejectedByTheMixedCaseGuardAlone() {
        let lex = ["istrings"]
        #expect(commitsAsTyped("isString", lexicon: lex))
        #expect(displaysAsTyped("isString", lexicon: lex))
    }

    // `OSString`: same shape, one key vanishes (`OString`), mixed case.
    @Test func osStringIsRejectedByTheMixedCaseGuardAlone() {
        let lex = ["ostrings"]
        #expect(commitsAsTyped("OSString", lexicon: lex))
        #expect(displaysAsTyped("OSString", lexicon: lex))
    }

    // `Montserrat`: a plain Capitalized word, so the case guard lets it through. The `s` tone
    // is swallowed, then `rr` cancels: TWO letters vanish (`Monterat`). Only the
    // exactly-one-key guard (G1) can reject this one; the lowercase form too.
    @Test func montserratIsRejectedByTheExactlyOneKeyGuardAlone() {
        let lex = ["monterats"]
        #expect(commitsAsTyped("Montserrat", lexicon: lex))
        #expect(displaysAsTyped("Montserrat", lexicon: lex))
        #expect(commitsAsTyped("montserrat", lexicon: lex))
        #expect(displaysAsTyped("montserrat", lexicon: lex))
    }

    // The guards must not switch the feature off: a Capitalized or ALL-CAPS habit word (one
    // key vanished, no mixed case) still gets the rule.
    @Test func capitalizedAndAllCapsHabitWordsStillGetTheRule() {
        let lex = ["unsuspected"]
        #expect(typeThroughEngine("Unssuspend ", config: on, lexicon: Lexicon(lex)) == "Unsuspend ")
        #expect(typeThroughEngine("UNSSUSPEND ", config: on, lexicon: Lexicon(lex)) == "UNSUSPEND ")
    }
}

// MARK: - What the screen shows while the word is still being typed

@Suite("CancelKeepsLiteralMidWordDisplay")
struct CancelKeepsLiteralMidWordDisplayTests {
    // A mouse click, a Cmd/Ctrl/Option chord or a focus change resets the engine WITHOUT
    // committing, so whatever the last keystroke displayed stays on screen as final text. A
    // word whose commit is right must therefore not flip to a wrong display on its way there.
    //
    // `missed` typed naturally: raw "miss" is a prefix of "missel", so the display keeps the
    // raw keys at the cancel key (4 keys in). The raw spelling stays alive past the cancel
    // ("misse" still begins "missel") and dies only at the inflection, so the cancel was not a
    // habit cancel. Later, composed "mised" becomes a prefix of "misedit" (depth 5 against raw
    // depth 5: no margin), and the "composed is a prefix" rule alone would flip the screen to
    // "mised" even though the commit keeps "missed". Measured on main: `missed` is shown and
    // committed as typed.
    private let lex = Lexicon(["misedit", "missel"])

    @Test func naturalMissedNeverFlashesTheCancelledSpelling() {
        #expect(typeStepwise("missed", config: on, lexicon: lex)
                == ["m", "mi", "mí", "miss", "misse", "missed"])
        #expect(typeThroughEngine("missed ", config: on, lexicon: lex) == "missed ")
    }

    // The display is a pure function of the keys. Typing, backspacing over the cancel key and
    // typing it again lands on the same screen.
    @Test func backspacingOverTheCancelKeyAndRetypingGivesTheSameScreen() {
        let engine = Engine(config: on)
        engine.lexicon = lex
        var acc: [Unicode.Scalar] = []
        func apply(_ r: EngineResult) {
            if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
            acc.append(contentsOf: r.text.unicodeScalars)
        }
        for ch in "missed" { apply(engine.process(KeyInput(ch))) }
        let direct = String(String.UnicodeScalarView(acc))
        for _ in 0..<3 { apply(engine.process(.backspace)) }          // back to "mis" -> "mí"
        #expect(String(String.UnicodeScalarView(acc)) == "mí")
        for ch in "sed" { apply(engine.process(KeyInput(ch))) }
        #expect(String(String.UnicodeScalarView(acc)) == direct)
        #expect(direct == "missed")
    }

    // The habit-cancel signature: the raw spelling dies exactly at the doubled key or one key
    // after it. `susspend`: the raw keys "suss" are a prefix of "sussultatory" (so the display
    // shows them at the cancel key, 4 keys in), but "sussp" is not: raw depth 4 is no deeper
    // than the cancel key's position, so the composed "susp" (a prefix of "suspend") takes over
    // at once instead of waiting for the margin. This is what the early rule is for.
    @Test func aRawSpellingThatDiesRightAtTheCancelKeyGivesWayToTheComposedPrefix() {
        let l = Lexicon(["suspend", "sussultatory"])
        #expect(typeStepwise("susspend", config: on, lexicon: l)
                == ["s", "su", "sú", "suss", "susp", "suspe", "suspen", "suspend"])
        #expect(typeThroughEngine("susspend ", config: on, lexicon: l) == "suspend ")
    }

    // `classs` is the same signature one key later (raw "class" is the word at the cancel key,
    // raw "classs" is no prefix): the screen shows `class` after the 6th key.
    @Test func classsShowsClassAfterTheSixthKey() {
        let l = Lexicon(["class", "clasp"])
        #expect(typeStepwise("classs", config: on, lexicon: l).last == "class")
    }

    // A raw display at the cancel key does not freeze the word either: the composed spelling
    // still wins by the margin (2) when the raw one is alive well past the cancel. Composed
    // "misilexample" is a prefix of "misilexamples" (depth grows with every key), raw
    // "missilexample" is a prefix of "missiles" up to "missile" (depth 7, past the cancel at 4).
    // The screen stays raw until composed is 2 letters deeper, which happens at the 10th key.
    @Test func aRawChoiceAliveBeyondTheCancelStillSwitchesByTheMargin() {
        let l = Lexicon(["misilexamples", "missiles"])
        let steps = typeStepwise("missilexample", config: on, lexicon: l)
        #expect(steps == ["m", "mi", "mí", "miss", "missi", "missil", "missile", "missilex",
                          "missilexa", "misilexam", "misilexamp", "misilexampl", "misilexample"])
        #expect(typeThroughEngine("missilexample ", config: on, lexicon: l) == "misilexample ")
    }

    // The other branch is today's behavior: when the cancel key itself was displayed as the
    // COMPOSED spelling (`uns`, `tas`), later keys follow the prefix rule as before.
    @Test func aComposedChoiceAtTheCancelKeyKeepsFollowingThePrefixRule() {
        // "tas" is a prefix of "task", "tass" is not: composed at the cancel key; `task` at k.
        let l = Lexicon(["task"])
        #expect(typeStepwise("tassk", config: on, lexicon: l) == ["t", "ta", "tá", "tas", "task"])
        let u = Lexicon(["unsuspected"])
        #expect(typeStepwise("unssuspend", config: on, lexicon: u).allSatisfy { !$0.contains("unss") })
    }
}
