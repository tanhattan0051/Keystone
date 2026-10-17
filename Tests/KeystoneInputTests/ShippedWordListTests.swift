// ShippedWordListTests.swift — pins the curated word lists (SupplementaryWords) by what the
// user SEES with the shipped config, not by list membership.
//
// Two bugs these lists had:
//  - `forceEnglishWords` held "six", so the common Vietnamese "sĩ" (bác sĩ, ca sĩ) was
//    untypeable.
//  - `protectedRealWords` held "iss/iff/orr/herr/oss/barr/maxx". That made the RAW spelling
//    of the OpenKey habit-cancel (i-s shows "í", second s cancels to "is") a dictionary
//    word, so the raw keys "iss" were committed instead of "is".

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("ShippedWordLists", .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct ShippedWordListTests {
    @Test func sixIsTheVietnameseSyllable() {
        #expect(typeShipped("six") == "sĩ ")
    }

    @Test(arguments: [
        ("iss", "is"), ("iff", "if"), ("orr", "or"), ("herr", "her"),
        ("oss", "os"), ("barr", "bar"), ("maxx", "max"),
    ])
    func habitCancelCommitsTheShortWord(raw: String, expected: String) {
        #expect(typeShipped(raw) == expected + " ")
    }

    @Test(arguments: [("hass", "has"), ("ussing", "using"), ("usses", "uses")])
    func habitCancelOfCommonInflections(raw: String, expected: String) {
        #expect(typeShipped(raw) == expected + " ")
    }

    @Test(arguments: ["using", "uses"])
    func naturalInflectionsCommitThemselves(word: String) {
        #expect(typeShipped(word) == word + " ")
    }

    // Known limit, unchanged by this fix: "has" is a VALID Vietnamese syllable (há), so
    // restoreIfInvalid never reverts it and no lexicon entry can change that (it would need a
    // Lớp B force-English entry, which would shadow há). Only the habit "hass" yields "has".
    @Test func naturalHasStaysTheVietnameseSyllable() {
        #expect(typeShipped("has") == "há ")
    }

    @Test(arguments: ["box", "row", "test", "reset"])
    func shadowingWhitelistWordsStayEnglish(word: String) {
        #expect(typeShipped(word) == word + " ")
    }

    // Accepted cost of dropping the protection: the rare words now commit the shorter word.
    @Test(arguments: [("Herr", "Her"), ("OSS", "OS"), ("Barr", "Bar"), ("Maxx", "Max")])
    func rareNaturalWordsNowCommitTheShorterWord(raw: String, committed: String) {
        let screen = typeShipped(raw)
        print("NATURAL", raw, "->", screen)
        #expect(screen == committed + " ")
    }

    @Test func removedProtectionsAreNoLongerListed() {
        for w in ["iss", "iff", "orr", "herr", "oss", "barr", "maxx"] {
            #expect(!SupplementaryWords.protectedRealWords.contains(w), "\(w) must not be protected")
        }
        #expect(!SupplementaryWords.forceEnglishWords.contains("six"))
    }

    // Reported, not decided: the owner seeded "box" and "row" knowingly. This pins which other
    // Telex key sequences still produce the shadowed Vietnamese words (all 2-4 key sequences
    // starting with b / r over a-z, [ and ]; clean spellings only matter, see below).
    @Test func shadowedVietnameseWordsStillHaveAnotherSpelling() {
        let found = shadowedSpellings()
        print("SHADOW-PROBE", found)
        // rơ: "r[" and "ro[" are the clean spellings; "r[" + a tone key + z is a tone-then-clear
        // detour. bõ: no clean spelling; "bo" + a tone key + "x" only works by re-toning an
        // already-toned o (a tone overwrite, not a deliberate spelling).
        #expect(found["rơ"]?.contains("r[") == true)
        #expect(found["rơ"]?.contains("ro[") == true)
        #expect(Set(found["bõ"] ?? []) == ["bofx", "bojx", "borx", "bosx"])
    }

    private func shadowedSpellings() -> [String: [String]] {
        let targets: Set<String> = ["bõ", "rơ"]
        let letters = Array("abcdefghijklmnopqrstuvwxyz[]")
        var candidates: [String] = []
        for first in ["b", "r"] {
            for a in letters {
                candidates.append(first + String(a))
                for b in letters {
                    candidates.append(first + String(a) + String(b))
                    for c in letters { candidates.append(first + String(a) + String(b) + String(c)) }
                }
            }
        }
        var out: [String: [String]] = [:]
        for k in candidates {
            let s = String(typeShipped(k).dropLast())
            if targets.contains(s) { out[s, default: []].append(k) }
        }
        return out
    }
}
