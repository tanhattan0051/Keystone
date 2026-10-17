// MacroTriggerValidationTests.swift — TDD suite for `MacroTable.triggerProblem`.
//
// The rule duplicates the engine's private `isWordChar`, so besides the pure
// table-style tests there is a BEHAVIOURAL cross-check that drives a real
// Engine: a trigger is valid iff the macro actually fires. If the engine's
// word-character rule ever changes, the cross-check goes red.

import Testing
@testable import KeystoneEngine

private let allMethods: [InputMethod] = [.telex, .vni, .simpleTelex1, .simpleTelex2]

@Suite("MacroTriggerProblemPure")
struct MacroTriggerProblemPureTests {
    @Test func plainLettersAreValid() {
        for method in allMethods {
            #expect(MacroTable.triggerProblem("vt", inputMethod: method, expandInEnglishMode: false) == nil)
        }
    }

    @Test func emptyTrigger() {
        #expect(MacroTable.triggerProblem("", inputMethod: .telex, expandInEnglishMode: false) == .empty)
    }

    @Test func whitespaceIsReported() {
        #expect(MacroTable.triggerProblem("x y", inputMethod: .telex, expandInEnglishMode: false) == .containsWhitespace)
        #expect(MacroTable.triggerProblem("xy ", inputMethod: .vni, expandInEnglishMode: true) == .containsWhitespace)
        #expect(MacroTable.triggerProblem("a\tb", inputMethod: .telex, expandInEnglishMode: false) == .containsWhitespace)
    }

    @Test func accentedAndDStrokeLettersAreNotRawLetters() {
        #expect(MacroTable.triggerProblem("đc", inputMethod: .telex, expandInEnglishMode: false) == .nonRawLetter("đ"))
        #expect(MacroTable.triggerProblem("sá", inputMethod: .telex, expandInEnglishMode: false) == .nonRawLetter("á"))
        #expect(MacroTable.triggerProblem("ư", inputMethod: .vni, expandInEnglishMode: false) == .nonRawLetter("ư"))
    }

    @Test func nonRawLetterMessageTellsToTypeRawKeys() {
        let message = MacroTable.triggerProblem("đc", inputMethod: .telex, expandInEnglishMode: false)?.message ?? ""
        #expect(message.contains("ddc"))
    }

    @Test func digitIsBoundaryInTelexButWordCharInVNI() {
        #expect(MacroTable.triggerProblem("k2", inputMethod: .telex, expandInEnglishMode: false) == .boundaryCharacter("2"))
        #expect(MacroTable.triggerProblem("k2", inputMethod: .simpleTelex1, expandInEnglishMode: true) == .boundaryCharacter("2"))
        #expect(MacroTable.triggerProblem("k2", inputMethod: .vni, expandInEnglishMode: false) == nil)
    }

    @Test func brackets() {
        #expect(MacroTable.triggerProblem("a[b", inputMethod: .telex, expandInEnglishMode: false) == nil)
        #expect(MacroTable.triggerProblem("a]", inputMethod: .simpleTelex2, expandInEnglishMode: false) == nil)
        #expect(MacroTable.triggerProblem("a[b", inputMethod: .vni, expandInEnglishMode: false) == .boundaryCharacter("["))
    }

    @Test func punctuationIsBoundary() {
        #expect(MacroTable.triggerProblem("a.b", inputMethod: .telex, expandInEnglishMode: false) == .boundaryCharacter("."))
        #expect(MacroTable.triggerProblem(":D", inputMethod: .telex, expandInEnglishMode: false) == .boundaryCharacter(":"))
    }

    @Test func everyProblemHasAMessage() {
        let problems: [MacroTriggerProblem] = [.empty, .containsWhitespace, .nonRawLetter("đ"), .boundaryCharacter("2")]
        for p in problems { #expect(!p.message.isEmpty) }
    }
}

// MARK: - Behavioural cross-check against the real Engine

private func macroFires(trigger: String, method: InputMethod) -> Bool {
    let marker = "<<FIRED>>"
    let config = EngineConfig(
        inputMethod: method,
        macrosEnabled: true,
        macros: [MacroRule(trigger: trigger, replacement: marker)]
    )
    let engine = Engine(config: config)
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    for ch in trigger + " " { apply(engine.process(KeyInput(ch))) }
    apply(engine.flush())
    return String(String.UnicodeScalarView(acc)).contains(marker)
}

@Suite("MacroTriggerProblemMatchesEngine")
struct MacroTriggerProblemMatchesEngineTests {
    // ASCII-only on purpose: a non-ASCII letter such as "đ" IS accumulated if
    // fed directly as a character (`isLetter`), but a real keyboard never
    // produces it as a raw key, so `triggerProblem` rejects it as
    // `.nonRawLetter` regardless of what the engine would do. Those are covered
    // in the pure suite above.
    private static let triggers = [
        "vt", "VT", "Vt", "dd", "ddc", "k2", "2k", "k22", "a.b", "a-b", "x y",
        "a[b", "[a", "a]", "[]", "a,", ":D", "k1k", "tt", "as", "hn", "a_b", "a/b",
    ]

    @Test(arguments: allMethods)
    func firesIffNoProblem(method: InputMethod) {
        for trigger in Self.triggers {
            let problem = MacroTable.triggerProblem(trigger, inputMethod: method, expandInEnglishMode: false)
            let fired = macroFires(trigger: trigger, method: method)
            #expect(fired == (problem == nil),
                    "trigger \(trigger.debugDescription) method \(method): fired=\(fired) problem=\(String(describing: problem))")
        }
    }
}
