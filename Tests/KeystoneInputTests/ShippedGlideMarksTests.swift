// ShippedGlideMarksTests.swift — gi-/qu- words with the mark typed after the
// vowel run, through the shipped config (lexicon + force-English included), so
// the engine fix is proven to survive the app's restore/spell-check layers.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("ShippedGlideMarks",
       .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct ShippedGlideMarksTests {
    @Test(arguments: [
        ("giayas", "giấy "), ("giaays", "giấy "), ("giuawx", "giữa "),
        ("gieengs", "giếng "), ("quaya", "quây "),
    ])
    func telex(_ keys: String, _ expected: String) {
        #expect(typeShipped(keys) == expected)
    }

    // qu must NOT be folded in the Telex circumflex test: English `queue`
    // would otherwise become quêu (a valid syllable the lexicon cannot rescue).
    @Test(arguments: [
        ("queue", "queue "), ("queues", "queues "), ("queuer", "queuer "),
    ])
    func englishQueueStaysEnglish(_ keys: String, _ expected: String) {
        #expect(typeShipped(keys) == expected)
    }

    @Test(arguments: [
        ("luu7", "lưu "), ("giay61", "giấy "), ("huou7", "hươu "),
        ("giua74", "giữa "), ("quan6", "quân "),
    ])
    func vni(_ keys: String, _ expected: String) {
        var cfg = shippedConfig
        cfg.inputMethod = .vni
        #expect(typeShipped(keys, config: cfg) == expected)
    }
}
