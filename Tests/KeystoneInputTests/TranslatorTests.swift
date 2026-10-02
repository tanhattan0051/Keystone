// TranslatorTests.swift — pure unit tests for KeyTranslator.decide.
//
// KeyTranslator has no engine, no I/O: every case here is a direct
// RawKey -> KeyDecision mapping check, per the design spec Part B.

import Testing
@testable import KeystoneInput

@Suite("Translator")
struct TranslatorTests {
    @Test func letter() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, chars: "a")) == .character("a"))
    }

    @Test func uppercaseLetterCarriesCase() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, shift: true, chars: "A")) == .character("A"))
    }

    @Test func space() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 49, chars: " ")) == .character(" "))
    }

    @Test func digit() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, chars: "5")) == .character("5"))
    }

    @Test func backspace() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 51, chars: "")) == .backspace)
    }

    @Test func returnKey() {
        // Return finalizes the word AND starts a new sentence for
        // autoCapitalize — see Contracts.swift's `.commitNewline` doc comment.
        #expect(KeyTranslator.decide(RawKey(keyCode: 36, chars: "\r")) == .commitNewline)
    }

    @Test func keypadEnterKey() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 76, chars: "\r")) == .commitNewline)
    }

    @Test func tabKeyStaysCommitPassthrough() {
        // Tab (and the other nav/commit keys) finalize the word but do NOT
        // start a new sentence — only Return/KeypadEnter do that.
        #expect(KeyTranslator.decide(RawKey(keyCode: 48, chars: "")) == .commitPassthrough)
    }

    @Test func arrowLeft() {
        // Arrows move the caret to text the engine never saw, so they also
        // make it forget the sentence position — see `.commitCaretMove`.
        #expect(KeyTranslator.decide(RawKey(keyCode: 123, chars: "")) == .commitCaretMove)
    }

    @Test func caretMoveKeysForgetTheSentencePosition() {
        // Left, Right, Down, Up, Home, End, PageUp, PageDown.
        for keyCode in [123, 124, 125, 126, 115, 119, 116, 121] {
            #expect(KeyTranslator.decide(RawKey(keyCode: keyCode, chars: "")) == .commitCaretMove,
                    "keyCode \(keyCode)")
        }
    }

    @Test func escape() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 53, chars: "")) == .commitPassthrough)
    }

    @Test func forwardDeleteStaysCommitPassthrough() {
        // ForwardDelete never changes what PRECEDES the caret, so the sentence
        // position is still trustworthy after it.
        #expect(KeyTranslator.decide(RawKey(keyCode: 117, chars: "")) == .commitPassthrough)
    }

    @Test func caretMoveWithAModifierIsStillAReset() {
        // Option+Left (word jump) is a chord: the modifier check comes first.
        #expect(KeyTranslator.decide(RawKey(keyCode: 123, option: true, chars: "")) == .resetPassthrough)
    }

    @Test func cmdAIsAShortcut() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, command: true, chars: "a")) == .resetPassthrough)
    }

    @Test func ctrlKey() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, control: true, chars: "c")) == .resetPassthrough)
    }

    @Test func emptyCharsNonSpecial() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 999, chars: "")) == .passthrough)
    }
}
