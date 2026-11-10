// CollapseDoubledLiteralsTests.swift — the pure raw-restore escapes, and the
// commit decision that keeps a cancelled word's composed spelling when that is
// what the screen already shows.
//
// Telex: each `ww` pair -> `w` and `ddd` -> `dd`, as before (OpenKey-compatible:
// `www` is an escaped `w` plus a literal `w`, so `ww`). VNI: nothing at all (its
// escapes are digits, `w`/`d` are plain letters there).

import Testing
@testable import KeystoneEngine

@Suite("CollapseDoubledLiterals")
struct CollapseDoubledLiteralsTests {
    private func telex(_ s: String) -> String {
        String(Engine.collapseDoubledLiterals(Array(s), inputMethod: .telex))
    }
    private func vni(_ s: String) -> String {
        String(Engine.collapseDoubledLiterals(Array(s), inputMethod: .vni))
    }

    @Test func eachWwPairCollapsesToOne() {
        #expect(telex("wwin") == "win")
        #expect(telex("swwim") == "swim")
        #expect(telex("ww") == "w")
    }
    @Test func keepsTheFirstWsCase() {
        #expect(telex("Wwin") == "Win")
        #expect(telex("wWin") == "win")
    }
    @Test func longerRunsCollapsePairwiseLikeOpenKey() {
        // w,w is the escape for one literal w; the next w is literal (OpenKey's
        // tempDisableKey), so w,w,w reads "ww" and w,w,w,w reads "www".
        #expect(telex("www") == "ww")
        // (The engine never restores a vowel-less run: w,w,w,w shows and commits the
        // fold's "www"; ShippedCommitMatchesScreenTests pins that end to end.)
        #expect(telex("wwww") == "ww")
        #expect(telex("wrong") == "wrong")
    }
    @Test func twoSeparateTwoRunsEachCollapse() {
        #expect(telex("wwawwb") == "wawb")
    }
    @Test func dddRuleIsUnchanged() {
        #expect(telex("dddos") == "ddos")
        #expect(telex("dddong") == "ddong")
        #expect(telex("add") == "add")
        #expect(telex("buddy") == "buddy")
    }
    private func telexDropping(_ s: String, _ idx: Set<Int>) -> String {
        String(Engine.collapseDoubledLiterals(Array(s), inputMethod: .telex, dropping: idx))
    }
    @Test func droppingOmitsTheGivenIndices() {
        // The caller (the fold) names the circumflex-applying key; index 1 of aaa...
        #expect(telexDropping("aaapanel", [1]) == "aapanel")
        #expect(telexDropping("eeexit", [1]) == "eexit")
        #expect(telexDropping("AAa", [1]) == "Aa")
    }
    @Test func aRunOfThreeIsUntouchedWithoutIndices() {
        // Whether aaa is an escape depends on the fold, not on the pattern.
        #expect(telex("aaa") == "aaa")
        #expect(telex("aaapanel") == "aaapanel")
        #expect(telex("ooops") == "ooops")
    }
    @Test func droppingComposesWithDddAndWw() {
        #expect(telexDropping("aaadddos", [1]) == "aaddos")
        #expect(telexDropping("wwaaa", [3]) == "waa")
    }
    @Test func vniIsTheIdentity() {
        #expect(vni("dddos") == "dddos")
        #expect(vni("swwim") == "swwim")
        #expect(vni("www") == "www")
        #expect(vni("aaapanel") == "aaapanel")
        #expect(String(Engine.collapseDoubledLiterals(Array("aaa"), inputMethod: .vni, dropping: [1])) == "aaa")
    }
    @Test func simpleTelexBehavesLikeTelex() {
        #expect(String(Engine.collapseDoubledLiterals(Array("swwim"), inputMethod: .simpleTelex1)) == "swim")
        #expect(String(Engine.collapseDoubledLiterals(Array("swwim"), inputMethod: .simpleTelex2)) == "swim")
    }
}

@Suite("ChooseAtCommitAfterCancel")
struct ChooseAtCommitAfterCancelTests {
    // "songs" is a dictionary PREFIX here (of "songsters") but not a word, like the real
    // 1934 list; raws are never words unless a test inserts one.
    private let lex = Lexicon(["songsters", "task"])

    private func choose(_ composed: String, _ raws: [String], displayed: Bool,
                        _ lexicon: Lexicon? = nil) -> RestoreChoice {
        RestoreDecision.chooseAtCommitAfterCancel(
            composed: composed, raws: raws, lexicon: lexicon ?? lex, displayedComposed: displayed)
    }

    @Test func rawWinningWhileComposedIsOnScreenFlipsToComposed() {
        // The margin rule only sees depth 5 vs 5 if the prefix index really exists.
        #expect(lex.isPrefixIndexBuilt)
        #expect(lex.prefixDepth("songs") == 5)
        // Margin rule picks raw at commit (depth 5 vs 5); the screen shows composed.
        #expect(RestoreDecision.chooseAfterCancel(
            composed: "songs", raws: ["songss"], lexicon: lex, atCommit: true) == .raw)
        #expect(choose("songs", ["songss"], displayed: true) == .composed)
    }
    @Test func screenShowingRawKeepsTheOrdinaryCommitDecision() {
        #expect(choose("songs", ["songss"], displayed: false) == .raw)
    }
    @Test func aRawThatIsAWordStillWins() {
        let withRaw = Lexicon(["songsters", "songss"])
        #expect(choose("songs", ["songss"], displayed: true, withRaw) == .raw)
        // any of several raw spellings
        #expect(choose("songs", ["sonss", "songss"], displayed: true, withRaw) == .raw)
    }
    @Test func composedWinningIsUnchanged() {
        // composed is a word: ordinary rule 2 already says composed, with or without display.
        #expect(choose("task", ["tassk"], displayed: false) == .composed)
        #expect(choose("task", ["tassk"], displayed: true) == .composed)
    }
    @Test func subsequenceGuardStillRefusesComposed() {
        // composed is not obtainable from the raws by deleting characters
        #expect(choose("phone", ["fone"], displayed: true) == .raw)
    }
}
