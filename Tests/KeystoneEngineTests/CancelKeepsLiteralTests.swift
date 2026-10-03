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

// MARK: - RestoreDecision.chooseAfterCancel, pure

@Suite("ChooseAfterCancel")
struct ChooseAfterCancelTests {
    // One word, so every depth is easy to read off: "abcdefg".
    private let lex = Lexicon(["abcdefg"])

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
        // ...and any of several candidates is enough.
        #expect(commit("abcdefg", ["zzz", "tassk"], Lexicon(["abcdefg", "tassk"])) == .raw)
    }

    @Test func commitComposedInTheLexiconWins() {
        #expect(commit("abcdefg", ["abcxxfg"], lex) == .composed)
    }

    @Test func commitMarginBoundaryDepthDifferenceOneIsRawTwoIsComposed() {
        // composed "abcdexx": depth 5 ("abcde"), not a word.
        // raw "abcdxxx": depth 4 -> difference 1 -> raw.
        #expect(commit("abcdexx", ["abcdxxx"], lex) == .raw)
        // raw "abcxxxx": depth 3 -> difference 2 -> composed.
        #expect(commit("abcdexx", ["abcxxxx"], lex) == .composed)
        // difference 3 -> composed.
        #expect(commit("abcdexx", ["abxxxxx"], lex) == .composed)
    }

    @Test func commitUsesTheDeepestRaw() {
        // Two raw spellings (collapsed, as typed): depth 4 and 3 -> max 4.
        #expect(commit("abcdexx", ["abcxxxx", "abcdxxx"], lex) == .raw)
        #expect(commit("abcdexx", ["abcxxxx", "abxxxxx"], lex) == .composed)
    }

    @Test func commitOtherwiseRaw() {
        // Neither spelling is English-like at all.
        #expect(commit("xyz", ["xyzz"], lex) == .raw)
        // Composed no better than raw.
        #expect(commit("abcxxxx", ["abcxxxx"], lex) == .raw)
    }

    @Test func commitComparesLowercased() {
        #expect(commit("ABCDEFG", ["ABCXXFG"], lex) == .composed)
        #expect(commit("ABCDEXX", ["ABCXXXX"], lex) == .composed)
        #expect(commit("abcdexx", ["ABCDEFG"], lex) == .raw)   // raw is a word, however it is cased
    }

    @Test func commitWithAnUnbuiltIndexNeverPrefersComposedByDepth() {
        var stale = Lexicon()
        stale.insert("abcdefg")
        // Depth is 0 on both sides: 0 >= 0 + 2 is false -> raw.
        #expect(commit("abcdexx", ["abcxxxx"], stale) == .raw)
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
        #expect(midWord("abcdexx", ["abcdxxx"], lex) == .raw)        // 5 vs 4
        #expect(midWord("abcdexx", ["abcxxxx"], lex) == .composed)   // 5 vs 3
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
}
