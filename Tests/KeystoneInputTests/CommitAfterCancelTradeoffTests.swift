// CommitAfterCancelTradeoffTests.swift — pins the accepted cost of committing the
// composed spelling when a cancelled word's screen already shows it
// (RestoreDecision.chooseAtCommitAfterCancel), and the bare-w-run override under
// non-shipped configs.

import Testing
@testable import KeystoneEngine

/// Out-of-dictionary words that the songss fix commits as the screen showed,
/// which is wrong for them. Accepted trade-off (see DECISIONS "www, VNI
/// collapse, and Space committing something other than the screen"): the same
/// rule fixes habit typing such as bitss/keyss. Pinned so a change here is
/// deliberate; if one of these starts committing the raw word, update that
/// section's numbers.
@Suite("KnownRegressionsOfCommitAfterCancel", .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct KnownRegressionsOfCommitAfterCancelTests {
    @Test func outOfDictionaryRawWordsCommitTheScreen() {
        #expect(typeShipped("troff") == "trof ")
        #expect(typeShipped("purrs") == "purs ")
        #expect(typeShipped("bitss") == "bits ")
        #expect(typeShipped("keyss") == "keys ")
    }
}

@Suite("WwwOtherConfigs", .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct WwwOtherConfigsTests {
    private func cfg(_ edit: (inout EngineConfig) -> Void) -> EngineConfig {
        var c = shippedConfig
        edit(&c)
        return c
    }
    @Test func bareWRunOverrideIsOffWithoutLiteralAfterCancel() {
        let noLAC = cfg { $0.literalAfterCancel = false }
        #expect(typeShipped("wwww", config: noLAC) == "ww ")
        // Mixed-case run: no longer collapsed by finalize (a run of three is literal).
        #expect(typeShipped("Www", config: noLAC) == "Www ")
    }
    /// Known, non-shipped-config limitation: with spellCheck off (no eager
    /// restore) the mid-word fold shows `wwi` for `wwwi` while the commit keeps
    /// the three typed w's. The commit is the faithful one; pinned so the
    /// difference is not silent.
    @Test func noSpellWRunScreenDiffersFromCommitKnown() {
        let noSpell = cfg { $0.spellCheck = false }
        #expect(screenWhileTyping("wwwi", config: noSpell) == "wwi")
        #expect(typeShipped("wwwi", config: noSpell) == "wwwi ")
        #expect(typeShipped("www", config: noSpell) == "www ")
    }
}
