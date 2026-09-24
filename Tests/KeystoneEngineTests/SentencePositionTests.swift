// SentencePositionTests.swift — TDD suite for the pure `SentencePosition`
// state machine (see DECISIONS.md "Auto-capitalize: dấu kết câu phải có
// khoảng trắng theo sau"). A "." "!" "?" only starts a new sentence once
// whitespace confirms it, and only when it was actually glued to real text
// on the way in — one reached after whitespace or an opening bracket
// ("hoa . lan", "x != y", "(!)") never confirms, no matter what follows. A
// letter or digit glued onto a pending terminator cancels it back to
// `settled` instead ("readme.md" stays lowercase; "1.1 Giới" keeps the
// capital "1" already earned). A closer (`) ] } ” ’ »`) forces glue back on
// and closes an UNCONFIRMABLE aside ("(...). Sau" capitalizes "Sau"), but
// leaves a CONFIRMABLE pending alone ("(hoa.) Lan" still works). Straight
// quotes and ordinary punctuation (including markdown closers `* _ \` ~` and
// a bare or glued "=") stay fully transparent, so "**chú ý.** Tiếp" still
// capitalizes past the closing `**`. `.afterReset` is the position right
// after `Engine.reset()`/`resetInactive()` — see its own doc comment. These
// tests exercise `SentencePosition.after(boundary:committedWord:)` directly,
// independent of `Engine` — the integration-level behavior (through
// `process`/`finalize`) is covered by `EngineTogglesTests.swift`'s
// `AutoCapitalizeTerminatorNeedsWhitespace` suite.

import Testing
@testable import KeystoneEngine

// MARK: - Static constants / isSentenceStart

@Suite("SentencePositionConstants")
struct SentencePositionConstantsTests {
    @Test func sentenceStartConstantIsSentenceStart() {
        #expect(SentencePosition.sentenceStart.isSentenceStart == true)
    }

    @Test func midSentenceConstantIsNotSentenceStart() {
        #expect(SentencePosition.midSentence.isSentenceStart == false)
    }

    @Test func settledSentenceStartWithAPendingTerminatorIsNotYetASentenceStart() {
        // A pending terminator is, by definition, unconfirmed — "1." the
        // instant it's typed must not read as sentence-initial yet.
        let pending = SentencePosition(settled: .sentenceStart, pending: .confirmable, gluedToText: true)
        #expect(pending.isSentenceStart == false)
    }

    @Test func afterResetIsMidSentenceGluedWithNoPendingTerminator() {
        // A reset assumes real text already precedes the caret (glue true),
        // but is NOT itself a sentence start — see `.afterReset`'s doc
        // comment in SentencePosition.swift.
        #expect(SentencePosition.afterReset
            == SentencePosition(settled: .midSentence, pending: nil, gluedToText: true))
        #expect(SentencePosition.afterReset.isSentenceStart == false)
    }
}

// MARK: - Committing a word collapses to mid-sentence + glued, cancelling any pending terminator

@Suite("SentencePositionCommittedWord")
struct SentencePositionCommittedWordTests {
    private static let starts: [SentencePosition] = [
        .sentenceStart,
        .midSentence,
        SentencePosition(settled: .sentenceStart, pending: .confirmable, gluedToText: true),
        SentencePosition(settled: .midSentence, pending: .unconfirmable, gluedToText: false),
    ]

    @Test(arguments: starts)
    func committedWordWithNilBoundaryCollapsesToMidSentenceGlued(_ start: SentencePosition) {
        // `nil` boundary = flush()/Tab/arrows with no character of their
        // own (see Engine.flush). Committing a word still consumes any
        // pending sentence-start/terminator even with no boundary character
        // at all — "hoa lan" + flushNewline() mid-word still commits "lan"
        // as ordinary mid-sentence text.
        let after = start.after(boundary: nil, committedWord: true)
        #expect(after == SentencePosition(settled: .midSentence, pending: nil, gluedToText: true))
    }

    @Test(arguments: starts)
    func committedWordGluedAfterTerminatorCancelsItEvenBehindClosingPunctuation(_ start: SentencePosition) {
        // "readme.md": the "md" glues directly onto the "." with no
        // whitespace between them, so it must NOT be treated as sentence-
        // initial even though a terminator may have been pending. Closing
        // punctuation right after that committed word (e.g. a quote)
        // doesn't resurrect the terminator either, since the word commit
        // already collapsed the base state before the punctuation is even
        // looked at.
        let after = start.after(boundary: "\"", committedWord: true)
        #expect(after.settled == .midSentence)
        #expect(after.pending == nil)
    }

    @Test(arguments: starts)
    func committedWordThenSpaceNeverResurrectsAPriorPendingTerminator(_ start: SentencePosition) {
        // "readme.md ": the word commit already cancelled any pending
        // terminator; the space that follows must not resurrect it, since
        // there's no pending terminator left to promote.
        let after = start.after(boundary: " ", committedWord: true)
        #expect(after == SentencePosition(settled: .midSentence, pending: nil, gluedToText: false))
    }

    @Test(arguments: starts)
    func committedWordThenTerminatorOpensAFreshConfirmableWindow(_ start: SentencePosition) {
        // A terminator right after a committed word is always glued to real
        // text, so it always opens a CONFIRMABLE window, regardless of
        // whatever was pending before this word committed.
        for ch: Character in [".", "!", "?"] {
            let after = start.after(boundary: ch, committedWord: true)
            #expect(after == SentencePosition(settled: .midSentence, pending: .confirmable, gluedToText: true))
        }
    }
}

// MARK: - No word composing (Engine's rawKeys-empty early-return path, or an
// English-mode boundary with nothing buffered)

@Suite("SentencePositionNoWord")
struct SentencePositionNoWordTests {
    @Test(arguments: [SentencePosition.sentenceStart, .midSentence])
    func nilBoundaryWithNoWordLeavesStateUnchanged(_ start: SentencePosition) {
        // `nil` = flush()/Tab with nothing composing: no new information at
        // all, so the state must be left exactly as it was — including a
        // pending terminator surviving a Tab (documented limitation).
        let pending = SentencePosition(settled: start.settled, pending: .unconfirmable, gluedToText: true)
        #expect(start.after(boundary: nil, committedWord: false) == start)
        #expect(pending.after(boundary: nil, committedWord: false) == pending)
    }

    @Test(arguments: [SentencePosition.sentenceStart, .midSentence])
    func newlineAlwaysStartsASentenceEvenWithNoWord(_ start: SentencePosition) {
        #expect(start.after(boundary: "\n", committedWord: false) == .sentenceStart)
        let pending = SentencePosition(settled: start.settled, pending: .confirmable, gluedToText: true)
        #expect(pending.after(boundary: "\n", committedWord: false) == .sentenceStart)
    }

    // -- Opening a pending terminator: confirmable vs. unconfirmable --

    @Test(arguments: [SentencePosition.sentenceStart, .midSentence])
    func terminatorGluedToPriorTextOpensAConfirmableWindow(_ start: SentencePosition) {
        // Reached with nothing composing but glued to real text just typed
        // (a digit, a word commit, another terminator, a closer) — e.g. the
        // "." in "2020." or the second "." in "..". `settled` is left as-is:
        // it's the resume target, not touched until the window closes.
        let glued = SentencePosition(settled: start.settled, pending: nil, gluedToText: true)
        for ch: Character in [".", "!", "?"] {
            let after = glued.after(boundary: ch, committedWord: false)
            #expect(after == SentencePosition(settled: start.settled, pending: .confirmable, gluedToText: true))
        }
    }

    @Test(arguments: [SentencePosition.sentenceStart, .midSentence])
    func terminatorNotGluedToPriorTextOpensAnUnconfirmableWindow(_ start: SentencePosition) {
        // Reached right after whitespace or an opening bracket ("hoa .
        // lan", "(!)", "x != y") — `gluedToText == false` — so it can NEVER
        // become a sentence start, only resume where it was.
        let notGlued = SentencePosition(settled: start.settled, pending: nil, gluedToText: false)
        for ch: Character in [".", "!", "?"] {
            let after = notGlued.after(boundary: ch, committedWord: false)
            #expect(after == SentencePosition(settled: start.settled, pending: .unconfirmable, gluedToText: true))
        }
    }

    @Test(arguments: [SentencePosition.Pending.confirmable, .unconfirmable])
    func aRunOfTerminatorsInheritsTheFirstOnesKind(_ kind: SentencePosition.Pending) {
        // "?!" / "..." / "?." — only the FIRST terminator in a run actually
        // saw whether it was glued to text; the rest just extend the same
        // open question, whatever kind it already is.
        let pending = SentencePosition(settled: .midSentence, pending: kind, gluedToText: true)
        for ch: Character in [".", "!", "?"] {
            let after = pending.after(boundary: ch, committedWord: false)
            #expect(after == SentencePosition(settled: .midSentence, pending: kind, gluedToText: true))
        }
    }

    // -- Whitespace resolves a pending terminator --

    @Test(arguments: [SentencePosition.Settled.sentenceStart, .midSentence])
    func whitespaceConfirmsAConfirmablePendingTerminatorIntoASentenceStart(_ settled: SentencePosition.Settled) {
        let pending = SentencePosition(settled: settled, pending: .confirmable, gluedToText: true)
        #expect(pending.after(boundary: " ", committedWord: false) == .sentenceStart)
    }

    @Test(arguments: [SentencePosition.Settled.sentenceStart, .midSentence])
    func whitespaceResumesAnUnconfirmablePendingTerminatorAtItsSettledValue(_ settled: SentencePosition.Settled) {
        // "hoa . lan" stays lowercase "lan": whitespace never confirms an
        // unconfirmable terminator, no matter how much whitespace follows —
        // it just resumes exactly where `settled` already was.
        let pending = SentencePosition(settled: settled, pending: .unconfirmable, gluedToText: true)
        let after = pending.after(boundary: " ", committedWord: false)
        #expect(after == SentencePosition(settled: settled, pending: nil, gluedToText: false))
    }

    @Test(arguments: [SentencePosition.Settled.sentenceStart, .midSentence])
    func whitespaceWithNothingPendingLeavesSettledAloneAndClearsGlue(_ settled: SentencePosition.Settled) {
        let glued = SentencePosition(settled: settled, pending: nil, gluedToText: true)
        let after = glued.after(boundary: " ", committedWord: false)
        #expect(after == SentencePosition(settled: settled, pending: nil, gluedToText: false))
    }

    // -- A glued letter/digit cancels a pending terminator back to `settled` --

    @Test(arguments: ["5", "0", "m"])
    func alphanumericCancelsAConfirmablePendingTerminatorBackToSettled(_ ch: Character) {
        // "3.14" and "readme.md" both stay mid-sentence: `settled` here is
        // already `.midSentence`, so cancelling back to it changes nothing
        // visible, but it's still the same cancel path as the sentence-
        // start case below. Only Telex digits reach this path in practice
        // (letters, VNI digits and English-mode digits are word chars and
        // arrive via `committedWord`); "m" pins the letter half of the rule.
        let pending = SentencePosition(settled: .midSentence, pending: .confirmable, gluedToText: true)
        let after = pending.after(boundary: ch, committedWord: false)
        #expect(after == SentencePosition(settled: .midSentence, pending: nil, gluedToText: true))
    }

    @Test(arguments: ["5", "0", "m"])
    func alphanumericCancelsAPendingTerminatorBackToASentenceStartSettled(_ ch: Character) {
        // This is the R3 fix: "1.1 Giới thiệu" — the "1" cancels the "."
        // but `settled` was `.sentenceStart` (inherited from `flushNewline`),
        // so the line-start capital survives the cancel.
        let pending = SentencePosition(settled: .sentenceStart, pending: .unconfirmable, gluedToText: true)
        let after = pending.after(boundary: ch, committedWord: false)
        #expect(after == SentencePosition(settled: .sentenceStart, pending: nil, gluedToText: true))
    }

    @Test(arguments: ["5", "0", "m"])
    func alphanumericWithNothingPendingLeavesSettledAloneAndSetsGlue(_ ch: Character) {
        let after = SentencePosition.midSentence.after(boundary: ch, committedWord: false)
        #expect(after == SentencePosition(settled: .midSentence, pending: nil, gluedToText: true))
    }

    // -- Opening brackets/quotes clear glue but leave settled/pending untouched --

    @Test(arguments: ["(", "[", "{", "\u{201C}", "\u{2018}", "\u{00AB}"],
                      [SentencePosition.Pending.unconfirmable, .confirmable])
    func openersClearGlueButLeaveSettledAndPendingUntouched(_ ch: Character, _ pending: SentencePosition.Pending) {
        // Parameterized over BOTH pending kinds: an opener reached from an
        // `.unconfirmable` pending (opened inside the same bracket, e.g.
        // "(!)") and from a `.confirmable` one (opened BEFORE the bracket,
        // e.g. "hoa.(x)") behave identically — the opener only ever touches
        // `gluedToText`, never `pending` itself, regardless of its kind.
        let glued = SentencePosition(settled: .midSentence, pending: pending, gluedToText: true)
        let after = glued.after(boundary: ch, committedWord: false)
        #expect(after == SentencePosition(settled: .midSentence, pending: pending, gluedToText: false))
    }

    @Test func openingCharsAtASentenceStartWithNoPendingAreANoOp() {
        // A leading "- " bullet or "(" right at a sentence start (existing
        // behavior: `dashBulletAtLineStartCapitalizes`) — there's no
        // pending terminator to touch, so this is simply a no-op on
        // `.sentenceStart` (it was already `gluedToText == false`).
        #expect(SentencePosition.sentenceStart.after(boundary: "-", committedWord: false) == .sentenceStart)
        #expect(SentencePosition.sentenceStart.after(boundary: "(", committedWord: false) == .sentenceStart)
    }

    // -- A closer forces glue on, and closes an UNCONFIRMABLE pending (but leaves a CONFIRMABLE one alone) --

    @Test(arguments: [")", "]", "}", "\u{201D}", "\u{2019}", "\u{00BB}"])
    func closerClosesAnUnconfirmablePendingTerminatorBackToSettled(_ ch: Character) {
        // "(...). Sau", "(!). Sau", "quá :). Mai": a closer ends the
        // editorial aside/emoticon it was part of, so an UNCONFIRMABLE
        // pending opened inside it (glued to nothing — right after "("/a
        // space) is closed back to `settled`, with `gluedToText` forced to
        // true so a terminator reached right after the closer CAN open a
        // fresh confirmable window.
        let pending = SentencePosition(settled: .midSentence, pending: .unconfirmable, gluedToText: true)
        let after = pending.after(boundary: ch, committedWord: false)
        #expect(after == SentencePosition(settled: .midSentence, pending: nil, gluedToText: true))
    }

    @Test(arguments: [")", "]", "}", "\u{201D}", "\u{2019}", "\u{00BB}"])
    func closerLeavesAConfirmablePendingTerminatorAlone(_ ch: Character) {
        // "(hoa.) Lan", "**chú ý.** Tiếp": a pending opened BEFORE the
        // bracket (glued to real text) is not this closer's business — it
        // is left exactly as-is, still open, only `gluedToText` is forced.
        let pending = SentencePosition(settled: .midSentence, pending: .confirmable, gluedToText: true)
        let after = pending.after(boundary: ch, committedWord: false)
        #expect(after == pending)
    }

    @Test(arguments: [")", "]", "}", "\u{201D}", "\u{2019}", "\u{00BB}"])
    func closerWithNothingPendingForcesGlueOn(_ ch: Character) {
        // "quá :). Mai", "vui quá =)). Mai": nothing pending yet at the
        // closer itself, but it must still set `gluedToText = true` so a
        // terminator reached right after it opens a CONFIRMABLE window, not
        // an unconfirmable one.
        let notPending = SentencePosition(settled: .midSentence, pending: nil, gluedToText: false)
        let after = notPending.after(boundary: ch, committedWord: false)
        #expect(after == SentencePosition(settled: .midSentence, pending: nil, gluedToText: true))
    }

    // -- Everything else (straight quotes, ordinary punctuation incl. "=") is fully transparent --

    @Test(arguments: [
        "\"", "'", ",", ";", ":", "-", "*", "_", "`", "~", "|", "/", "@", "#", "=",
    ])
    func straightQuotesAndOrdinaryPunctuationLeaveAPendingTerminatorFullyUntouched(_ ch: Character) {
        // Covers straight quotes ("hoa.\" Lan" still starts a new sentence
        // after the closing quote) AND markdown closers (`**chú ý.** Tiếp`,
        // `_hoa._ Lan` — the emphasis marker right after the "." must not
        // read as the word that glues onto it and cancels the pending
        // sentence start) AND a bare or glued "=" ("x = a", "a!=b",
        // "a !== b" all stay lowercase without any dedicated "=" rule —
        // see DECISIONS.md).
        let pending = SentencePosition(settled: .midSentence, pending: .confirmable, gluedToText: true)
        #expect(pending.after(boundary: ch, committedWord: false) == pending)
        let notPending = SentencePosition(settled: .sentenceStart, pending: nil, gluedToText: false)
        #expect(notPending.after(boundary: ch, committedWord: false) == notPending)
    }

    @Test(arguments: [SentencePosition.sentenceStart, .midSentence])
    func nilBoundaryWithNoWordLeavesStateUnchangedAcrossSettledValues(_ start: SentencePosition) {
        #expect(start.after(boundary: nil, committedWord: false) == start)
    }
}

// MARK: - Pure pin for the R3 line-start-heading fix (Engine-level integration
// is covered by EngineTogglesTests.swift's AutoCapitalizeTerminatorNeedsWhitespace)

@Suite("SentencePositionLineStartDigit")
struct SentencePositionLineStartDigitTests {
    @Test func aBareDigitRightAtASentenceStartKeepsSettledButIsNotYetASentenceStart() {
        // A unit glued straight onto a line-start digit ("3h", "10h", "5kg",
        // "2nd") is a continuation of that token, not a sentence-initial
        // word of its own — see `isSentenceStart`'s doc comment. `settled`
        // still survives as `.sentenceStart` (so "1.1 Giới thiệu" keeps its
        // capital once the glue clears), but `isSentenceStart` itself must
        // read false while still glued.
        let afterDigit = SentencePosition.sentenceStart.after(boundary: "3", committedWord: false)
        #expect(afterDigit.settled == .sentenceStart)
        #expect(afterDigit.gluedToText == true)
        #expect(afterDigit.isSentenceStart == false)

        // The following space clears the glue, so a word starting there
        // ("3 Lan") is sentence-initial again.
        let afterSpace = afterDigit.after(boundary: " ", committedWord: false)
        #expect(afterSpace.isSentenceStart == true)
    }
}
