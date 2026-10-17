// RegularInflectionTests.swift — `Lexicon.containsWordOrRegularInflection` and
// how the cancel decision uses it (hermetic lexicons, no system dictionary).
//
// The bug: the 1934 Webster list lacks regular inflections (`carries`,
// `presses`, `errs`), while the one-letter-shorter composed spelling of a
// cancel happens to be a word (`caries`, `preses`, `ers`), so "composed is a
// word" used to win and Space rewrote what the user typed.

import Testing
@testable import KeystoneEngine

@Suite("Regular inflections")
struct RegularInflectionTests {
    private let lex = Lexicon([
        "carry", "press", "err", "box", "moss", "key", "fuss", "bake", "stop",
        "class", "pass", "bit", "is", "has", "use", "song", "go", "bus", "wish",
        "church", "hero", "buzz", "pus",
        "caries", "preses", "ers", "moses",
    ])

    @Test("A plain word counts")
    func plainWord() {
        #expect(lex.containsWordOrRegularInflection("press"))
        #expect(lex.containsWordOrRegularInflection("PRESS"))
        #expect(!lex.containsWordOrRegularInflection("zzz"))
    }

    @Test("-ies -> stem + y")
    func iesSuffix() {
        #expect(lex.containsWordOrRegularInflection("carries"))
        #expect(!lex.containsWordOrRegularInflection("buies"))
    }

    @Test("-es only after s, x, z, ch, sh, o")
    func esSuffix() {
        for w in ["presses", "mosses", "boxes", "buzzes", "churches", "wishes", "heroes"] {
            #expect(lex.containsWordOrRegularInflection(w), "\(w)")
        }
        // `keyes` would need stem "key", which does not end in a sibilant or o.
        #expect(!lex.containsWordOrRegularInflection("keyes"))
        #expect(!lex.containsWordOrRegularInflection("bakees"))
    }

    @Test("-s only when the stem does not end in s, x, z, ch, sh")
    func sSuffix() {
        #expect(lex.containsWordOrRegularInflection("errs"))
        #expect(lex.containsWordOrRegularInflection("keys"))
        #expect(lex.containsWordOrRegularInflection("songs"))
        // The habit-cancel guards: the stem ends in s/x/z/ch/sh.
        for w in ["classs", "passs", "keyss", "iss", "hass", "boxs", "buzzs", "churchs", "wishs", "buss"] {
            #expect(!lex.containsWordOrRegularInflection(w), "\(w)")
        }
        // `bitss` has the stem "bits", which is not itself in this lexicon.
        #expect(!lex.containsWordOrRegularInflection("bitss"))
    }

    @Test("-ed / -ing: stem, stem+e, undoubled consonant; stem of 3+ letters")
    func edIng() {
        for w in ["fussed", "fussing", "baked", "baking", "stopped", "stopping", "boxed"] {
            #expect(lex.containsWordOrRegularInflection(w), "\(w)")
        }
        // 2-letter stems never count.
        #expect(!lex.containsWordOrRegularInflection("going"))
        #expect(!lex.containsWordOrRegularInflection("ised"))
        #expect(!lex.containsWordOrRegularInflection("ussing"))
    }

    @Test("-ed / -ing: a tripled final consonant is the habit's extra key, not a doubled one")
    func tripledConsonantIsNotUndoubled() {
        let l = Lexicon(["ass", "buff", "err", "stop"])
        for w in ["asssed", "bufffing", "errring", "bufffed"] {
            #expect(!l.containsWordOrRegularInflection(w), "\(w)")
        }
        for w in ["buffing", "erred", "stopped"] {
            #expect(l.containsWordOrRegularInflection(w), "\(w)")
        }
    }

    @Test("Cancel at commit: a regular inflection as raw wins over a composed word")
    func commitRawInflectionWins() {
        #expect(RestoreDecision.chooseAfterCancel(
            composed: "caries", raws: ["carries"], lexicon: lex, atCommit: true) == .raw)
        #expect(RestoreDecision.chooseAfterCancel(
            composed: "preses", raws: ["presses"], lexicon: lex, atCommit: true) == .raw)
        #expect(RestoreDecision.chooseAfterCancel(
            composed: "ers", raws: ["errs"], lexicon: lex, atCommit: true) == .raw)
        #expect(RestoreDecision.chooseAfterCancel(
            composed: "moses", raws: ["mosses"], lexicon: lex, atCommit: true) == .raw)
    }

    @Test("Cancel mid-word: the screen agrees with Space")
    func midWordRawInflectionWins() {
        #expect(RestoreDecision.chooseAfterCancel(
            composed: "caries", raws: ["carries"], lexicon: lex, atCommit: false) == .raw)
        #expect(RestoreDecision.chooseMidWordAfterCancel(
            composed: "caries", raws: ["carries"], lexicon: lex, rawShownAtCancelOfLength: nil) == .raw)
    }

    @Test("Habit cancels are not inflections: composed still wins")
    func habitCancelsStillCancel() {
        let habit = Lexicon(["class", "pass", "bit", "bits", "is", "has", "key", "keys", "task"])
        for (composed, raw) in [("class", "classs"), ("pass", "passs"), ("bits", "bitss"),
                                ("keys", "keyss"), ("is", "iss"), ("has", "hass")] {
            #expect(RestoreDecision.chooseAfterCancel(
                composed: composed, raws: [raw], lexicon: habit, atCommit: true) == .composed, "\(raw)")
        }
    }

    @Test("chooseAtCommitAfterCancel: an inflected raw is vouched for, not overridden by the screen")
    func atCommitGuard() {
        #expect(RestoreDecision.chooseAtCommitAfterCancel(
            composed: "caries", raws: ["carries"], lexicon: lex, displayedComposed: true) == .raw)
    }
}
