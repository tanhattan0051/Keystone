// ShippedInflectionTests.swift — natural typing of regular inflections the
// 1934 Webster list lacks, and the habit cancels that must keep working, with
// the shipped config and the real lexicon. See RegularInflectionTests for the
// pure rules.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("Shipped: cancel vs regular inflections",
       .enabled(if: systemDictExists, "requires /usr/share/dict/words"))
struct ShippedInflectionTests {
    @Test("Natural inflections survive Space and the screen agrees",
          arguments: ["carries", "presses", "errs", "mosses", "fussed"])
    func naturalInflections(word: String) {
        #expect(screenWhileTyping(word) == word)
        #expect(typeShipped(word) == word + " ")
    }

    @Test("Habit cancels still cancel",
          arguments: [
              ("tassk", "task"), ("classs", "class"), ("passs", "pass"), ("bitss", "bits"),
              ("keyss", "keys"), ("iss", "is"), ("hass", "has"), ("ussing", "using"),
              ("usses", "uses"), ("songss", "songs"), ("unssuspend", "unsuspend"),
              ("gooogle", "google"),
          ])
    func habitCancels(typed: String, expected: String) {
        #expect(typeShipped(typed) == expected + " ")
    }
}
