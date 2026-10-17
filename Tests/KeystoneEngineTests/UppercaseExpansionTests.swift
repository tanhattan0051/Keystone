// UppercaseExpansionTests.swift — a letter whose uppercase is two characters
// (ß -> "SS") must not trap the engine. Auto-capitalize and a capitalized raw
// revert both uppercase a typed letter; Character("SS") is a runtime trap, so the
// uppercase has to stay a String and be emitted character by character.

import Testing
@testable import KeystoneEngine

@Suite("Uppercase expansion") struct UppercaseExpansionTests {
    private func type(_ keys: String, config: EngineConfig) -> String {
        let engine = Engine(config: config)
        var screen: [Unicode.Scalar] = []
        func apply(_ r: EngineResult) {
            screen.removeLast(min(r.backspaceCount, screen.count))
            screen.append(contentsOf: r.text.unicodeScalars)
        }
        for ch in keys { apply(engine.process(KeyInput(ch))) }
        apply(engine.flush())
        return String(String.UnicodeScalarView(screen))
    }

    private var capitalizing: EngineConfig {
        var config = EngineConfig()
        config.autoCapitalize = true
        return config
    }

    @Test func autoCapitalizeUppercasesAnExpandingLetterAtSentenceStart() {
        #expect(type("ßa ", config: capitalizing) == "SSa ")
    }

    @Test func autoCapitalizedRawRevertStartingWithAnExpandingLetter() {
        // "ßtext" has no legal Vietnamese reading, so it reverts to the raw keys,
        // and the revert capitalizes the first one.
        let out = type("ßtext ", config: capitalizing)
        #expect(out == "SStext ")
    }

    @Test func capitalizedRawRevertViaShiftedTypingDoesNotTrap() {
        var config = capitalizing
        config.restoreIfInvalid = true
        #expect(type("ßwxyz ", config: config).hasPrefix("SS"))
    }

    @Test func compoundTableAlsoSurvives() {
        var config = capitalizing
        config.codeTable = .unicodeCompound
        #expect(type("ßa ", config: config) == "SSa ")
    }

    @Test func ordinaryCapitalizationIsUnchanged() {
        #expect(type("vieejt ", config: capitalizing) == "Việt ")
    }
}
