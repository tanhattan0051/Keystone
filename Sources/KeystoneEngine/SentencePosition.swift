// SentencePosition.swift — pure sentence-start tracker behind `autoCapitalize`
// and macro `autoCapitalize`. See DECISIONS.md "Auto-capitalize: dấu kết câu
// phải có khoảng trắng theo sau".

/// Where the next committed word sits relative to a sentence boundary.
///
/// A plain Bool can't express the middle state: right after a "." the engine
/// doesn't know yet whether it ends a sentence ("Xin chào. Bạn") or is glued
/// inside a token ("readme.md", "3.14"). Only whitespace settles it.
enum SentencePosition: Equatable {
    /// The next committed word is NOT sentence-initial.
    case midSentence
    /// Just saw "." "!" "?" — becomes a sentence start once whitespace
    /// follows, unless a letter or digit gets glued onto it first.
    case afterTerminator
    /// The next committed word IS sentence-initial.
    case sentenceStart

    /// The position after one boundary character (`nil` for a flush —
    /// Tab/arrows/Escape — which carries no character), given whether that
    /// boundary also committed a word.
    func after(boundary: Character?, committedWord: Bool) -> SentencePosition {
        // A committed word consumes a pending sentence start (it WAS the
        // sentence-initial word) and cancels a pending terminator (it was
        // glued on with no whitespace, as in "readme.md").
        let base: SentencePosition = committedWord ? .midSentence : self

        guard let ch = boundary else {
            // Tab may be focus change, shell completion or indent, and arrows
            // move the caret somewhere unknown: neither confirm nor cancel.
            return base
        }

        if ch.isNewline {
            // Live Return goes through `flushNewline`/`flushInactiveNewline`;
            // this covers a "\n" handed to `process`/`processInactive` directly.
            return .sentenceStart
        }
        if ch == "." || ch == "!" || ch == "?" {
            return .afterTerminator
        }
        if ch.isWhitespace {
            // Must come after `isNewline` (a newline is whitespace too).
            // Whitespace only confirms a pending terminator; on its own it
            // says nothing about sentences.
            return base == .afterTerminator ? .sentenceStart : base
        }
        if ch.isLetter || ch.isNumber {
            // Only Telex digits actually arrive here — letters, VNI digits and
            // English-mode digits are word chars and come via `committedWord`.
            // Either way, an alphanumeric glued to the terminator ("3.14")
            // means it was not a sentence end.
            return base == .afterTerminator ? .midSentence : base
        }
        // Other punctuation carries no sentence information: closing quotes,
        // brackets and markdown closers stay transparent ("**chú ý.** Tiếp"),
        // and a leading "- " bullet keeps a sentence start
        // (`dashBulletAtLineStartCapitalizes`).
        return base
    }
}
