// CancelKeepsLiteralTests.swift — TDD suite for "after a Telex/VNI cancel, keep
// the cancelled literal" (OpenKey `checkRestoreIfWrongSpelling` parity), see
// DECISIONS.md "Huỷ dấu xong giữ nguyên chữ đã huỷ".
//
// The habit: the user sees a tone appear (`s u s` -> `sú`) and presses the key
// again to cancel it. The eager restore (`spellCheck`) used to render the RAW
// keystrokes, cancel key included, so the screen showed `suss`, then
// `susspend`. OpenKey restores raw keys only while some vowel still carries a
// tone or quality mark; once a cancel has stripped them it leaves the on-screen
// word alone. Keystone now does the same, and at the word boundary it keeps
// the cancelled literal unless the RAW keystrokes are themselves a dictionary
// word (`class`, `message`, `pass` typed naturally).
//
// Same replay helpers as EagerRestoreTests.swift (file-private there).

import Testing
@testable import KeystoneEngine

private func typeThroughEngine(_ keys: String, config: EngineConfig, lexicon: Lexicon? = nil) -> String {
    let engine = Engine(config: config)
    engine.lexicon = lexicon
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    for ch in keys {
        apply(engine.process(KeyInput(ch)))
    }
    apply(engine.flush())
    return String(String.UnicodeScalarView(acc))
}

/// Screen contents after EACH key of `keys` (no trailing flush).
private func typeStepwise(_ keys: String, config: EngineConfig, lexicon: Lexicon? = nil) -> [String] {
    let engine = Engine(config: config)
    engine.lexicon = lexicon
    var acc: [Unicode.Scalar] = []
    var steps: [String] = []
    for ch in keys {
        let r = engine.process(KeyInput(ch))
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
        steps.append(String(String.UnicodeScalarView(acc)))
    }
    return steps
}

private let on = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                               freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)
private let vniOn = EngineConfig(inputMethod: .vni, restoreIfInvalid: true, allowFreeToneMark: true,
                                  freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)
/// "unsuspend" is deliberately absent (row 3: the whole point is a word the
/// dictionary does not have).
private let lex = Lexicon(["suspend", "class", "pass", "message", "task"])

// MARK: - Rows 1-10, 14: the cancelled literal stays on screen

@Suite("CancelKeepsLiteralTelex")
struct CancelKeepsLiteralTelexTests {
    @Test func suspendTraceKeepsTheLiteralAfterCancel() {
        // Row 1: s u s -> "sú"; the second s cancels the tone and leaves "sus"
        // (NOT "suss"), and everything after is literal.
        #expect(typeStepwise("susspend", config: on, lexicon: lex)
                == ["s", "su", "sú", "sus", "susp", "suspe", "suspen", "suspend"])
    }

    @Test func suspendCommitsComposed() {
        // Row 2: the raw "susspend" is not a word, the composed one is.
        #expect(typeThroughEngine("susspend ", config: on, lexicon: lex) == "suspend ")
    }

    @Test func wordMissingFromTheDictionaryStillCommitsWithoutTheCancelKey() {
        // Row 3: this is the bug that was visible — "unsuspend" is not in the
        // dictionary and used to commit as "unssuspend".
        #expect(typeThroughEngine("unssuspend ", config: on, lexicon: lex) == "unsuspend ")
    }

    @Test func unsuspendTraceShowsTheCancelImmediately() {
        // Row 4: the 4th key is the cancelling s.
        let steps = typeStepwise("unssuspend", config: on, lexicon: lex)
        #expect(steps[3] == "uns")
    }

    @Test func tripledLetterCollapsesToTheDictionaryWord() {
        // Row 5: c l a s s s -> cancel on the 5th key, 6th key literal.
        #expect(typeThroughEngine("classs ", config: on, lexicon: lex) == "class ")
    }

    @Test func naturalDoubleThatIsADictionaryWordKeepsBothLetters() {
        // Row 6: raw "class" is a word, so the commit takes the raw spelling.
        #expect(typeThroughEngine("class ", config: on, lexicon: lex) == "class ")
    }

    @Test func naturalDoubleShowsOneLetterLessWhileTyping() {
        // Row 7: accepted trade-off, pinned. The cancel is indistinguishable
        // from a natural double until the boundary, so mid-word it shows
        // "clas"; the space then restores "class" (row 6).
        #expect(typeStepwise("class", config: on, lexicon: lex).last == "clas")
    }

    @Test func messageTypedEitherWayCommitsTheDictionaryWord() {
        // Row 8: "messsage" (cancel habit) and "message" (natural double).
        #expect(typeThroughEngine("messsage ", config: on, lexicon: lex) == "message ")
        #expect(typeThroughEngine("message ", config: on, lexicon: lex) == "message ")
    }

    @Test func taskTypedWithTheCancelHabit() {
        // Row 9.
        #expect(typeThroughEngine("tassk ", config: on, lexicon: lex) == "task ")
    }

    @Test func naturalDoubleOutsideTheDictionaryLosesALetter() {
        // Row 10: OpenKey parity, pinned on purpose. "messi" is not in the
        // test dictionary, and typing the double s is exactly what a cancel
        // looks like, so the commit keeps the cancelled literal "mesi".
        #expect(typeThroughEngine("messi ", config: on, lexicon: lex) == "mesi ")
    }

    @Test func autoCapitalizeStillAppliesToTheKeptLiteral() {
        // Row 14.
        var cfg = on
        cfg.autoCapitalize = true
        #expect(typeThroughEngine("unssuspend ", config: cfg, lexicon: lex) == "Unsuspend ")
    }
}

// MARK: - Rows 11, 12, 13: the rule must not fire where it does not apply

@Suite("CancelKeepsLiteralNotApplicable")
struct CancelKeepsLiteralNotApplicableTests {
    @Test func literalAfterCancelOffIsUnchanged() {
        // Row 11: without literalAfterCancel the engine never sets `cancelled`.
        var cfg = on
        cfg.literalAfterCancel = false
        #expect(typeThroughEngine("unssuspend ", config: cfg, lexicon: lex) == "unssuspend ")
    }

    @Test func noLexiconIsUnchanged() {
        // Row 12: without a dictionary there is nothing to decide with, so
        // today's behavior (raw restore, eager and at commit) stays.
        #expect(typeThroughEngine("unssuspend ", config: on, lexicon: nil) == "unssuspend ")
        #expect(typeStepwise("unssuspend", config: on, lexicon: nil)
                == ["u", "un", "ún", "unss", "unssu", "unssus", "unssusp", "unssuspe", "unssuspen", "unssuspend"])
    }

    @Test func cancelThatLeavesAQualityMarkIsUnchanged() {
        // Row 13: `ee` -> ê is still on the word after the tone cancel, and
        // OpenKey restores raw keys while any vowel carries a mark.
        #expect(typeThroughEngine("vieetss ", config: on, lexicon: lex) == "vieetss ")
        #expect(typeStepwise("vieetss", config: on, lexicon: lex)
                == ["v", "vi", "vie", "viê", "viêt", "viết", "vieetss"])
    }

    @Test func cancelWhileAToneSurvivesIsUnchanged() {
        // The tone clause of the guard (not a table row): the sắc was set
        // BEFORE the circumflex was cancelled, so `comp.tone` is still not
        // ngang and the rule must not fire. Pins today's commit (raw
        // restore), not an endorsement of the odd mid-word rendering.
        #expect(typeThroughEngine("tosooo ", config: on, lexicon: lex) == "tosooo ")
    }
}

// MARK: - Row 15: VNI

@Suite("CancelKeepsLiteralVNI")
struct CancelKeepsLiteralVNITests {
    @Test func vniDigitCancelKeepsTheLiteral() {
        // Row 15: a1 -> á, the second 1 cancels and the digit stays literal.
        // VNI's cancel does set `Composition.cancelled` (same `.literal`
        // signal as Telex), so this matches Telex. Before the change: "a11 ".
        #expect(typeThroughEngine("a11 ", config: vniOn, lexicon: lex) == "a1 ")
    }
}

// MARK: - The pure commit decision

@Suite("RestoreDecisionChooseAfterCancel")
struct RestoreDecisionChooseAfterCancelTests {
    @Test func rawWinsOnlyWhenTheRawKeysAreADictionaryWord() {
        #expect(RestoreDecision.chooseAfterCancel(raw: "class", lexicon: lex) == .raw)
        #expect(RestoreDecision.chooseAfterCancel(raw: "classs", lexicon: lex) == .composed)
        #expect(RestoreDecision.chooseAfterCancel(raw: "unssuspend", lexicon: lex) == .composed)
    }

    @Test func lookupIsCaseInsensitive() {
        #expect(RestoreDecision.chooseAfterCancel(raw: "CLASS", lexicon: lex) == .raw)
    }
}
