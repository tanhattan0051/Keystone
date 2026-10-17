// FocusResetPolicyTests.swift — pins the pure pieces behind AppModel's AX
// focus-change reset (Sources/KeystoneInput/FocusResetPolicy.swift).

import Testing
@testable import KeystoneInput

@Suite("FocusResetPolicy")
struct FocusResetPolicyTests {
    // MARK: classify

    private func kind(_ keyCode: UInt16, _ chars: String, _ mods: ModifierSet = []) -> MonitoredKeyKind {
        FocusResetPolicy.classify(keyCode: keyCode, characters: chars, modifiers: mods)
    }

    @Test func lettersDigitsAndBracketsAreWordKeys() {
        #expect(kind(2, "d") == .wordKey)
        #expect(kind(2, "D", [.shift]) == .wordKey)
        #expect(kind(18, "1") == .wordKey)
        #expect(kind(33, "[") == .wordKey)
        #expect(kind(30, "]") == .wordKey)
        #expect(kind(0, "ư") == .wordKey)
    }

    @Test func spacePunctuationAndSymbolsAreBoundaries() {
        #expect(kind(49, " ") == .boundary)
        #expect(kind(43, ",") == .boundary)
        #expect(kind(47, ".") == .boundary)
        #expect(kind(24, "=") == .boundary)
        #expect(kind(20, "#") == .boundary)
    }

    @Test func chordsAreBoundaries() {
        #expect(kind(0, "a", [.command]) == .boundary)
        #expect(kind(0, "a", [.control]) == .boundary)
        #expect(kind(0, "å", [.option]) == .boundary)
        #expect(kind(0, "A", [.shift]) == .wordKey)
    }

    @Test func navigationAndCommitKeysAreBoundaries() {
        for code: UInt16 in [36, 76, 48, 53, 117, 123, 124, 125, 126, 115, 119, 116, 121] {
            #expect(kind(code, "") == .boundary)
        }
    }

    @Test func backspaceIsNeutral() {
        #expect(kind(51, "\u{7F}") == .neutral)
    }

    @Test func functionKeysAndEmptyCharactersAreNeutral() {
        #expect(kind(122, "\u{F704}") == .neutral)   // F1
        #expect(kind(122, "") == .neutral)
        #expect(kind(0, "ab") == .neutral)           // not a single character
    }

    // MARK: WordStartTracker

    @Test func firstWordKeySetsStartAndLaterOnesKeepIt() {
        var t = WordStartTracker()
        #expect(t.currentWordStart == nil)
        t.record(.wordKey, at: 1.0)
        t.record(.wordKey, at: 2.0)
        #expect(t.currentWordStart == 1.0)
    }

    @Test func boundaryClearsAndNeutralKeeps() {
        var t = WordStartTracker()
        t.record(.wordKey, at: 1.0)
        t.record(.neutral, at: 1.5)
        #expect(t.currentWordStart == 1.0)
        t.record(.boundary, at: 2.0)
        #expect(t.currentWordStart == nil)
        t.record(.wordKey, at: 3.0)
        #expect(t.currentWordStart == 3.0)
    }

    @Test func resetClearsStart() {
        var t = WordStartTracker()
        t.record(.wordKey, at: 1.0)
        t.reset()
        #expect(t.currentWordStart == nil)
    }

    // MARK: policy

    @Test func noTriggerTimeResets() {
        #expect(FocusResetPolicy.shouldResetOnFocusChange(currentWordStart: 5, triggerTime: nil))
    }

    @Test func noWordStartResets() {
        #expect(FocusResetPolicy.shouldResetOnFocusChange(currentWordStart: nil, triggerTime: 5))
    }

    @Test func wordStartedBeforeTriggerResets() {
        #expect(FocusResetPolicy.shouldResetOnFocusChange(currentWordStart: 4.9, triggerTime: 5))
    }

    @Test func wordStartedAtOrAfterTriggerIsKept() {
        #expect(!FocusResetPolicy.shouldResetOnFocusChange(currentWordStart: 5, triggerTime: 5))
        #expect(!FocusResetPolicy.shouldResetOnFocusChange(currentWordStart: 5.5, triggerTime: 5))
    }
}
