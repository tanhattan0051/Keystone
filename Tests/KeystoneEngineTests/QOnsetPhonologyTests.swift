// QOnsetPhonologyTests.swift — pure table for Phonology.isLegalQOnset.

import Testing
@testable import KeystoneEngine

@Suite("q onset phonology")
struct QOnsetPhonologyTests {

    @Test("bare q is never a legal onset", arguments: ["a", "o", "u", "ê", "uy"])
    func bareQ(nucleus: String) {
        #expect(!Phonology.isLegalQOnset("q", nucleus: nucleus))
    }

    @Test("qu + plain o, u, ư is illegal", arguments: ["o", "oa", "u", "ư", "ưa"])
    func quIllegal(nucleus: String) {
        #expect(!Phonology.isLegalQOnset("qu", nucleus: nucleus))
    }

    @Test("qu + the real nuclei is legal",
          arguments: ["a", "ă", "â", "e", "ê", "i", "y", "ô", "ơ", "yê", "ôi", "ay", "âu", "ơi"])
    func quLegal(nucleus: String) {
        #expect(Phonology.isLegalQOnset("qu", nucleus: nucleus))
    }

    @Test("other onsets are untouched", arguments: ["", "c", "k", "gi", "ng"])
    func others(onset: String) {
        #expect(Phonology.isLegalQOnset(onset, nucleus: "o"))
        #expect(Phonology.isLegalQOnset(onset, nucleus: "u"))
    }
}
