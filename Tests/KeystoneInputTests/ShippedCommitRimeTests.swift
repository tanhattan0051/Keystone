// ShippedCommitRimeTests.swift — commit-time rime completeness through the
// shipped config (real lexicon, force-English). See DECISIONS.md
// "Commit-time rime completeness".

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("ShippedCommitRime", .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct ShippedCommitRimeTests {
    @Test(arguments: [
        ("saw", "saw "), ("AWS", "AWS "), ("things", "things "), ("disc", "disc "),
        ("ping", "ping "),
    ])
    func englishWordsKeepTheirLetters(_ keys: String, _ expected: String) {
        #expect(typeShipped(keys) == expected)
    }

    @Test(arguments: [
        ("awn", "ăn "), ("aan", "ân "), ("hoawcj", "hoặc "), ("khuaan", "khuân "),
        ("quaan", "quân "), ("tieengs", "tiếng "), ("yeen", "yên "), ("muoons", "muốn "),
        ("khuyeen", "khuyên "), ("tinhs", "tính "), ("ichs", "ích "),
        ("xengr", "xẻng "), ("xeengr", "xểng "), ("secs", "séc "),
    ])
    func vietnameseGuards(_ keys: String, _ expected: String) {
        #expect(typeShipped(keys) == expected)
    }

    @Test func keengfIsPinned() {
        #expect(typeShipped("keengf") == "kềng ")
    }

    @Test func midWordStaysEager() {
        #expect(screenWhileTyping("saw") == "să")
    }
}
