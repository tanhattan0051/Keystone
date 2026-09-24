// SentencePosition.swift — pure sentence-start tracker behind `autoCapitalize`
// and macro `autoCapitalize`. See DECISIONS.md "Auto-capitalize: dấu kết câu
// phải có khoảng trắng theo sau" for the glue-aware model below.

/// Where the next committed word sits relative to a sentence boundary, and
/// whether a "." "!" "?" just typed is still waiting on trailing whitespace
/// to decide whether it actually ends the sentence.
///
/// A plain two-state Bool can't represent this: right after a terminator the
/// engine doesn't yet know whether it ends a sentence ("Xin chào. Bạn") or is
/// glued inside a token ("readme.md", "1.1", "(!)"). `pending` holds that
/// open question; `settled` is the RESUME target once it closes — either
/// promoted to `.sentenceStart` by a confirming whitespace, or cancelled
/// back to whatever it already was by a glued letter/digit. `gluedToText` is
/// what tells a terminator reached after real text ("readme.", "1.1", a
/// closing paren) apart from one reached after whitespace or an opening
/// bracket ("hoa . lan", "(!)", "x != y") — only the former can become a
/// sentence start at all.
struct SentencePosition: Equatable {
    enum Settled: Equatable { case midSentence, sentenceStart }
    enum Pending: Equatable { case confirmable, unconfirmable }

    var settled: Settled
    var pending: Pending?
    /// The last thing typed was text a terminator can plausibly end — a
    /// word, a digit, a closer, or another terminator — as opposed to
    /// whitespace or an opening bracket/quote.
    var gluedToText: Bool

    static let sentenceStart = SentencePosition(settled: .sentenceStart, pending: nil, gluedToText: false)
    static let midSentence   = SentencePosition(settled: .midSentence,   pending: nil, gluedToText: false)

    /// The position right after `Engine.reset()`/`resetInactive()` (a mouse
    /// click, an app/keyboard-focus switch, a Cmd/Ctrl/Option chord, or
    /// deactivation — `EngineController.setActive(false)`, Vietnamese
    /// on→off). Unlike a brand-new `Engine`, a reset does NOT
    /// mean the caret sits at the true start of a document — there may be
    /// pasted text, pre-existing text, or a word typed while Vietnamese was
    /// off sitting right before it, invisible to the engine either way.
    /// `gluedToText: true` assumes the conservative case (real text already
    /// there), so a terminator typed right after a reset can still confirm
    /// on a following whitespace ("hoa" + reset() + ". lan " → "hoa. Lan ").
    /// The next WORD still does not capitalize on its own — `settled ==
    /// .midSentence` and `pending == nil` mean `isSentenceStart` is false
    /// until an actual terminator+whitespace is seen after the reset.
    static let afterReset = SentencePosition(settled: .midSentence, pending: nil, gluedToText: true)

    /// What `Engine.atSentenceStart` reads. A pending terminator is, by
    /// definition, not yet confirmed, so it must NOT count as a sentence
    /// start even when `settled == .sentenceStart` — e.g. "1." the instant
    /// it's typed, before the confirming whitespace (or cancelling digit)
    /// arrives. `!gluedToText` is what keeps a unit glued straight onto a
    /// digit or closer ("3h", "10h", "5kg", "2nd") from reading as a fresh
    /// sentence-initial word — it's a continuation of that token, not a
    /// sentence-initial word on its own, even though `settled ==
    /// .sentenceStart` survives the glued digit (see the letter/digit branch
    /// of `after` below). Whitespace, a newline and an opening bracket all
    /// clear the glue, so "1. Mục", "1.1 Giới thiệu", "hoa. 3 Lan" and
    /// "(Lan", "- Mục" are unaffected.
    var isSentenceStart: Bool { settled == .sentenceStart && pending == nil && !gluedToText }

    /// The position after one boundary character (`nil` for a flush —
    /// Tab/arrows/Escape — which carries no character of its own), given
    /// whether that boundary also committed a word.
    func after(boundary: Character?, committedWord: Bool) -> SentencePosition {
        // The committed word was already judged against the OLD `self` by
        // `finalize` (that decided whether IT capitalized); from here on it
        // is just mid-sentence text glued to whatever follows, cancelling
        // any pending terminator along with it — a word glued to a pending
        // terminator with no whitespace between ("readme.md", ".gitignore",
        // "...và") therefore stays lowercase, since the terminator never
        // gets its confirming whitespace.
        let s: SentencePosition = committedWord
            ? SentencePosition(settled: .midSentence, pending: nil, gluedToText: true)
            : self

        guard let ch = boundary else {
            // Tab/arrows/Escape carry no character of their own: documented
            // "Tab neither confirms nor cancels" — a stray focus change or
            // shell completion shouldn't flip capitalization either way.
            return s
        }

        if ch.isNewline {
            // A live Return goes through `flushNewline`/`flushInactiveNewline`
            // (which set this directly); this covers a "\n" handed straight
            // to `process`/`processInactive`.
            return .sentenceStart
        }
        if ch == "." || ch == "!" || ch == "?" {
            // A run like "?!" or "..." inherits the FIRST terminator's kind
            // — only that first one actually saw whether it was glued to
            // real text; the rest just extend the same open question.
            let pending = s.pending ?? (s.gluedToText ? .confirmable : .unconfirmable)
            return SentencePosition(settled: s.settled, pending: pending, gluedToText: true)
        }
        if ch.isWhitespace {
            // Must come after the `isNewline` check above (a newline is
            // whitespace too). Whitespace alone says nothing about
            // sentences — it only ever resolves an EXISTING pending
            // terminator, promoting a confirmable one to a real sentence
            // start or resuming an unconfirmable one right where it was.
            switch s.pending {
            case .confirmable:
                return .sentenceStart
            case .unconfirmable, nil:
                // "hoa . lan" stays lowercase "lan": a terminator reached
                // after whitespace (or with nothing glued before it) never
                // confirms, no matter how much more whitespace follows —
                // resume exactly at the pre-terminator `settled`.
                return SentencePosition(settled: s.settled, pending: nil, gluedToText: false)
            }
        }
        if ch.isLetter || ch.isNumber {
            // Only Telex digits actually reach this as a bare boundary
            // (letters, VNI digits and English-mode digits are word chars
            // and arrive via `committedWord` instead). Either way, gluing a
            // letter/digit straight onto a pending terminator means it
            // wasn't a sentence end — cancel back to `settled`, NOT
            // `.midSentence`: this is what fixes "1.1 Giới thiệu" and
            // "24.09 Họp" (the digit cancels the "." but the line-start
            // sentence start it inherited survives), while "hoa.5 lan"
            // (settled already `.midSentence` there) still stays lowercase.
            // Accepted limitation: a bare number at a sentence start
            // ("1. Mục", "3 Lan") keeps the capital the same way.
            return SentencePosition(settled: s.settled, pending: nil, gluedToText: true)
        }
        if ch == ")" || ch == "]" || ch == "}" || ch == "\u{201D}" || ch == "\u{2019}" || ch == "\u{00BB}" {
            // A closer is real text — an editorial aside or bracketed
            // clause just ended — so it forces `gluedToText = true`, even
            // when nothing was pending yet: this is what lets a terminator
            // reached RIGHT AFTER the closer ("(!). Sau", "quá :). Mai",
            // "=)). Mai") open a CONFIRMABLE window instead of an
            // unconfirmable one. If what was pending is itself
            // `.unconfirmable` — opened INSIDE this same bracket, glued to
            // nothing ("(...)", "(!)") — the closer ends that aside, so it's
            // closed back to `settled` with no resurrection. A `.confirmable`
            // pending (opened BEFORE the bracket, e.g. "hoa.) Lan" inside
            // "(hoa.) Lan") is left alone — the bracket is just ordinary
            // punctuation relative to that still-open question.
            let pending: Pending? = s.pending == .unconfirmable ? nil : s.pending
            return SentencePosition(settled: s.settled, pending: pending, gluedToText: true)
        }
        if ch == "(" || ch == "[" || ch == "{" || ch == "\u{201C}" || ch == "\u{2018}" || ch == "\u{00AB}" {
            // An opening bracket/quote never carries sentence-ending text
            // itself, so it clears the glue — this is what keeps an
            // editorial aside like "(!)" or "(...)" from opening a
            // CONFIRMABLE window: the "!"/"." right after "(" sees
            // `gluedToText == false`, exactly like one typed after
            // whitespace ("x != y", "hoa . lan"). `settled`/`pending` are
            // otherwise untouched — an opener right at a sentence start is
            // simply a no-op on it (`dashBulletAtLineStartCapitalizes`).
            return SentencePosition(settled: s.settled, pending: s.pending, gluedToText: false)
        }
        // Everything else — straight quotes/apostrophes and ordinary
        // punctuation `, ; : - * _ \` ~ | / @ # =` (including a bare or
        // glued "=", which carries no sentence information of its own: an
        // operator like "!=" already stays lowercase because the "!" that
        // opened it was either unconfirmable to begin with, reached after
        // whitespace or an opener, or — glued directly onto a word, "a!="
        // — gets judged against a still-PENDING state by the next word's
        // own commit, which never reads as a sentence start either way) —
        // is fully transparent: it neither confirms nor cancels a pending
        // terminator, nor changes the glue. This is what keeps "**chú ý.**
        // Tiếp", "(hoa.) Lan", "hoa.\" Lan" and a leading "- " bullet
        // working. A straight quote/apostrophe is ambiguous by design — right
        // after a word it inherits `gluedToText == true` and behaves like a
        // closer, right after whitespace it inherits `gluedToText == false`
        // and behaves like an opener — either way "leave everything as-is"
        // is the correct answer for it WHEN THE QUOTE IS WRAPPING REAL TEXT
        // (`"Đi thôi." Rồi`, `hoa." lan`). Accepted limitation: when the
        // quote instead wraps a PUNCTUATION-ONLY token (`"...". sau` — the
        // whole quoted span is itself just the terminator), the closing
        // quote never gets the CLOSER treatment (forcing `gluedToText =
        // true`) the way `)`/`”` do, so a "." right after it never opens a
        // fresh confirmable window — see DECISIONS.md "Accepted
        // limitations".
        return s
    }
}
