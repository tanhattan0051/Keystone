// ForceEnglishTests.swift — TDD suite for the "force-English whitelist"
// (Lớp B, `SupplementaryWords.forceEnglishWords` / `Engine.forceEnglish`):
// English words whose Telex keystrokes ALSO spell a VALID Vietnamese
// syllable, so `restoreIfInvalid` never reverts them and they stay
// Vietnamese today (`test`→tét, `reset`→rết, `row`→rơ, …). Unlike the
// lexicon-driven "restore chooses the composed word" feature, this is a
// small CURATED list of deliberate English-over-Vietnamese overrides — not a
// blanket "prefer English", which would break common Vietnamese words typed
// via English-looking keys (`car`→cả, `cow`→cơ, `bee`→bê). See DECISIONS.md
// "Force-English whitelist (Lớp B)".
//
// Driven through `EngineController` like `LexiconRestoreTests.swift`, but
// `typeAndFlush` (RealisticTyping.swift) has no way to inject a force-English
// list, so this file builds its own small local helper that also calls
// `EngineController.setForceEnglish`.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

private let appOn = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                                  freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)
private let appOff = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                                   freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: false)

/// Types `w` through a fresh `EngineController`, then a trailing space
/// (which commits the word like any other boundary), reconstructing the
/// on-screen text exactly as `EventTapController` would apply it (see
/// `applyRealistically` in RealisticTyping.swift). `force` is installed via
/// `EngineController.setForceEnglish` before typing starts, mirroring
/// `typeAndFlush`'s handling of `setLexicon`.
private func typeWord(_ w: String, config: EngineConfig, force: [String]) -> String {
    let c = EngineController(config: config)
    c.setForceEnglish(force.isEmpty ? nil : Lexicon(force))
    var acc: [Unicode.Scalar] = []
    for ch in w {
        applyRealistically(c.handle(letter(ch)), to: &acc)
    }
    applyRealistically(c.handle(RawKey(keyCode: 0, chars: " ")), to: &acc)   // trailing space commits
    return String(String.UnicodeScalarView(acc))
}

@Suite("ForceEnglishListedWordsWinAsEnglish")
struct ForceEnglishListedWordsWinAsEnglishTests {
    @Test(arguments: [
        "test", "reset", "six", "box", "row", "refer", "defer",
    ])
    func listedWordWinsOverVietnameseHomograph(word: String) {
        let result = typeWord(word, config: appOn, force: SupplementaryWords.forceEnglishWords)
        #expect(result == word + " ")
    }

    @Test func capitalizedRawKeystrokesArePreserved() {
        let result = typeWord("Test", config: appOn, force: SupplementaryWords.forceEnglishWords)
        #expect(result == "Test ")
    }
}

@Suite("ForceEnglishUnlistedStaysVietnamese")
struct ForceEnglishUnlistedStaysVietnameseTests {
    @Test func unlistedEnglishLookingWordsStillComposeVietnamese() {
        // Deliberately NOT seeded into forceEnglishWords — same Lớp B shape
        // as `test`/`reset`, but not curated in, so Vietnamese still wins.
        #expect(typeWord("rust", config: appOn, force: SupplementaryWords.forceEnglishWords) == "rút ")
        #expect(typeWord("tax", config: appOn, force: SupplementaryWords.forceEnglishWords) == "tã ")
        #expect(typeWord("max", config: appOn, force: SupplementaryWords.forceEnglishWords) == "mã ")
    }

    @Test func commonVietnameseWordsTypedViaEnglishLookingKeysAreUnaffected() {
        // THE load-bearing safety gate: a blanket "prefer English" would
        // break these every-day Vietnamese words. They must never be in
        // forceEnglishWords, and must compose normally regardless.
        #expect(typeWord("car", config: appOn, force: SupplementaryWords.forceEnglishWords) == "cả ")
        #expect(typeWord("cow", config: appOn, force: SupplementaryWords.forceEnglishWords) == "cơ ")
        #expect(typeWord("bee", config: appOn, force: SupplementaryWords.forceEnglishWords) == "bê ")
        #expect(typeWord("bus", config: appOn, force: SupplementaryWords.forceEnglishWords) == "bú ")
    }

    @Test func ordinaryVietnameseWordIsUnaffected() {
        #expect(typeWord("tieengs", config: appOn, force: SupplementaryWords.forceEnglishWords) == "tiếng ")
    }
}

@Suite("ForceEnglishInertWhenSpellCheckOff")
struct ForceEnglishInertWhenSpellCheckOffTests {
    @Test func listedWordStillComposesVietnameseWhenSpellCheckIsOff() {
        // The whitelist only wins at `finalize` when `config.spellCheck` is
        // on — with it off, `test` composes exactly as it always did.
        #expect(typeWord("test", config: appOff, force: SupplementaryWords.forceEnglishWords) == "tét ")
    }
}

@Suite("ForceEnglishListIntegrity")
struct ForceEnglishListIntegrityTests {
    @Test func allEntriesAreLowercase() {
        for w in SupplementaryWords.forceEnglishWords {
            #expect(w == w.lowercased(), "\(w) must be lowercase")
        }
    }

    @Test func noDuplicates() {
        let words = SupplementaryWords.forceEnglishWords
        #expect(Set(words).count == words.count)
    }

    @Test func disjointFromTheOtherSupplementaryLists() {
        let force = Set(SupplementaryWords.forceEnglishWords)
        #expect(force.isDisjoint(with: Set(SupplementaryWords.all)))
        #expect(force.isDisjoint(with: Set(SupplementaryWords.protectedRealWords)))
    }

    // Every entry must be a genuine Lớp B word: with spellCheck OFF and NO
    // force list, typing it composes a VALID Vietnamese syllable different
    // from the raw word — proving it really would collide with (and lose
    // to) a Vietnamese homograph, so listing it here is not dead weight.
    @Test func everyEntryIsAGenuineVietnameseHomographCollision() {
        for w in SupplementaryWords.forceEnglishWords {
            let composed = typeWord(w, config: appOff, force: [])
            #expect(composed != w + " ", "\(w) does not collide with a Vietnamese composition — dead weight")
        }
    }
}
