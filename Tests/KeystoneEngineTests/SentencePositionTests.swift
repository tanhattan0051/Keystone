// SentencePositionTests.swift — TDD suite for the pure `SentencePosition`
// state machine (see DECISIONS.md "Auto-capitalize: dấu kết câu phải có
// khoảng trắng theo sau"). A "." "!" "?" only starts a new sentence once
// whitespace confirms it; a letter or digit glued onto it cancels it back to
// mid-sentence instead ("readme.md" stays lowercase); any other punctuation
// (including markdown closers `* _ \` ~`) stays transparent, so "**chú ý.**
// Tiếp" still capitalizes past the closing `**`. These tests exercise
// `SentencePosition.after(boundary:committedWord:)` directly, independent of
// `Engine` — the integration-level behavior (through `process`/`finalize`)
// is covered by `EngineTogglesTests.swift`'s
// `AutoCapitalizeTerminatorNeedsWhitespace` suite.

import Testing
@testable import KeystoneEngine

// MARK: - Committing a word cancels a pending sentence-start/terminator

@Suite("SentencePositionCommittedWord")
struct SentencePositionCommittedWordTests {
    @Test func committedWordThenSpaceFromSentenceStartGoesMid() {
        // Committing a word consumes a pending sentence-start: the word that
        // was just typed is the sentence-initial one, so whatever follows is
        // no longer sentence-initial.
        #expect(SentencePosition.sentenceStart.after(boundary: " ", committedWord: true) == .midSentence)
    }

    @Test(arguments: [SentencePosition.sentenceStart, .afterTerminator, .midSentence])
    func committedWordThenTerminatorGoesToAfterTerminatorFromAnyState(_ start: SentencePosition) {
        // A terminator always opens a "maybe sentence end" window, regardless
        // of whether a word was just committed on the way in.
        #expect(start.after(boundary: ".", committedWord: true) == .afterTerminator)
        #expect(start.after(boundary: "!", committedWord: true) == .afterTerminator)
        #expect(start.after(boundary: "?", committedWord: true) == .afterTerminator)
    }

    @Test func committedWordThenNilFromSentenceStartGoesMid() {
        // `nil` boundary = flush()/Tab/arrows with no character of their own
        // (see Engine.flush). Committing a word still consumes the pending
        // sentence-start even with no boundary character at all.
        #expect(SentencePosition.sentenceStart.after(boundary: nil, committedWord: true) == .midSentence)
    }

    @Test func committedWordGluedAfterTerminatorCancelsItEvenBehindClosingPunctuation() {
        // "readme.md": the "md" glues directly onto the "." with no
        // whitespace between them, so it must NOT be treated as sentence-
        // initial even though a terminator was just seen. Closing punctuation
        // right after that committed word (e.g. a quote) doesn't resurrect
        // the terminator either, since the word commit already collapsed the
        // base state to `.midSentence` before the punctuation is even looked
        // at.
        #expect(SentencePosition.afterTerminator.after(boundary: "\"", committedWord: true) == .midSentence)
    }

    @Test func committedWordThenSpaceAfterTerminatorGoesMidSentence() {
        // "readme.md ": the word commit already cancelled the pending
        // terminator (see above); the space that follows must not resurrect
        // it, since there's no pending terminator left to promote.
        #expect(SentencePosition.afterTerminator.after(boundary: " ", committedWord: true) == .midSentence)
    }
}

// MARK: - No word composing (Engine's rawKeys-empty early-return path, or an
// English-mode boundary with nothing buffered)

@Suite("SentencePositionNoWord")
struct SentencePositionNoWordTests {
    @Test func spacePromotesOnlyAPendingTerminator() {
        #expect(SentencePosition.afterTerminator.after(boundary: " ", committedWord: false) == .sentenceStart)
        #expect(SentencePosition.midSentence.after(boundary: " ", committedWord: false) == .midSentence)
        #expect(SentencePosition.sentenceStart.after(boundary: " ", committedWord: false) == .sentenceStart)
    }

    @Test(arguments: [SentencePosition.sentenceStart, .afterTerminator, .midSentence])
    func terminatorWithNoWordOpensTheWindowFromAnyState(_ start: SentencePosition) {
        // English mode, and Engine's rawKeys-empty early-return path, both
        // route a lone terminator (nothing composing) through here too — see
        // "năm 2020. tiếp" in DECISIONS.md. Starting from `.sentenceStart` is
        // the transition behind "...vaf " -> "...và " and ".gitignore "
        // staying lowercase: a "." right after a newline (or any sentence start) opens a fresh
        // window instead of leaving the sentence start standing.
        #expect(start.after(boundary: ".", committedWord: false) == .afterTerminator)
    }

    @Test(arguments: [SentencePosition.sentenceStart, .afterTerminator, .midSentence])
    func newlineAlwaysStartsASentenceEvenWithNoWord(_ start: SentencePosition) {
        #expect(start.after(boundary: "\n", committedWord: false) == .sentenceStart)
    }

    // Any punctuation/symbol that isn't a letter or digit is transparent: it
    // neither confirms nor cancels a pending terminator. This covers closing
    // quotes/brackets ("Đi thôi.\" Rồi" still starts a new sentence after the
    // closing quote) AND markdown closers (`**chú ý.** Tiếp`, `_hoa._ Lan` —
    // the emphasis marker right after the "." must not read as the word
    // that glues onto it and cancels the pending sentence start).
    @Test(arguments: ["\"", "'", ")", "]", "\u{201D}", "*", "_", "`", "~", ",", "-", "(", "|"])
    func punctuationStaysTransparentOnAPendingTerminator(_ ch: Character) {
        #expect(SentencePosition.afterTerminator.after(boundary: ch, committedWord: false) == .afterTerminator)
    }

    @Test(arguments: ["5", "0", "m"])
    func alphanumericGluedToAPendingTerminatorCancelsIt(_ ch: Character) {
        // A terminator glued to a bare letter or digit means it wasn't a
        // sentence end after all: "3.14" and "readme.md" both stay
        // mid-sentence. Only Telex digits reach this path in practice
        // (letters, VNI digits and English-mode digits are word chars and
        // arrive via `committedWord`); "m" pins the letter half of the rule.
        #expect(SentencePosition.afterTerminator.after(boundary: ch, committedWord: false) == .midSentence)
    }

    @Test func openingCharsAtASentenceStartDoNotCancelIt() {
        // A leading "- " bullet or "(" right at a sentence start must not be
        // mistaken for the "cancel a pending terminator" case above — there
        // is no pending terminator here, so these are simply no-ops on
        // `.sentenceStart` (existing behavior: `dashBulletAtLineStartCapitalizes`).
        #expect(SentencePosition.sentenceStart.after(boundary: "-", committedWord: false) == .sentenceStart)
        #expect(SentencePosition.sentenceStart.after(boundary: "(", committedWord: false) == .sentenceStart)
    }

    @Test(arguments: [SentencePosition.sentenceStart, .afterTerminator, .midSentence])
    func nilBoundaryWithNoWordLeavesStateUnchanged(_ start: SentencePosition) {
        // `nil` = flush()/Tab with nothing composing: no new information at
        // all, so the state must be left exactly as it was.
        #expect(start.after(boundary: nil, committedWord: false) == start)
    }
}
