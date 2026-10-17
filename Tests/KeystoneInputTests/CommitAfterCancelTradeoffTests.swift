// CommitAfterCancelTradeoffTests.swift — pins the accepted cost of committing the
// composed spelling when a cancelled word's screen already shows it
// (RestoreDecision.chooseAtCommitAfterCancel).

import Testing
@testable import KeystoneEngine

/// Out-of-dictionary words that the songss fix commits as the screen showed,
/// which is wrong for them. Accepted trade-off (see DECISIONS "Space
/// commits what the cancel rule showed"): the same
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
