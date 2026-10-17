// CollapseDoubledLiteralsTests.swift — the pure raw-restore escapes, and the
// commit decision that keeps a cancelled word's composed spelling when that is
// what the screen already shows.
//
// `ww` -> `w` only for a run of EXACTLY two (so `www` stays `www`), `ddd` -> `dd`
// as before, and nothing at all in VNI (its escapes are digits, `w`/`d` are
// plain letters there).

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

    @Test func exactlyTwoWsCollapseToOne() {
        #expect(telex("wwin") == "win")
        #expect(telex("swwim") == "swim")
        #expect(telex("ww") == "w")
    }
    @Test func keepsTheFirstWsCase() {
        #expect(telex("Wwin") == "Win")
        #expect(telex("wWin") == "win")
    }
    @Test func runsOfOneOrThreeOrMoreWsAreLeftAlone() {
        #expect(telex("www") == "www")
        #expect(telex("wwww") == "wwww")
        #expect(telex("wrong") == "wrong")
        #expect(telex("wwwin") == "wwwin")
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
    @Test func vniIsTheIdentity() {
        #expect(vni("dddos") == "dddos")
        #expect(vni("swwim") == "swwim")
        #expect(vni("www") == "www")
    }
    @Test func bareWRunNeedsThreeOrMoreAndATelexMethod() {
        func run(_ s: String, _ m: InputMethod = .telex) -> Bool {
            Engine.isBareWRun(Array(s), inputMethod: m)
        }
        #expect(run("www") && run("wwww") && run("WwW"))
        #expect(!run("ww") && !run("w") && !run("wwin") && !run("wwwx"))
        #expect(!run("www", .vni))
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
