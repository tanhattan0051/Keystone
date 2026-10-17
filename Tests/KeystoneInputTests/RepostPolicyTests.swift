// RepostPolicyTests.swift — pins when the tap may re-emit the user's own
// physical key instead of synthesizing a text event (DECISIONS.md, "Re-emit the
// original key when the edit is just that key").

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("RepostPolicy")
struct RepostPolicyTests {
    private func edit(_ bs: Int, _ text: String) -> EngineResult {
        EngineResult(backspaceCount: bs, text: text)
    }

    @Test func plainCharacterAppendIsReposted() {
        #expect(RepostPolicy.canRepostOriginal(decision: .character("a"), edit: edit(0, "a")))
        #expect(RepostPolicy.canRepostOriginal(decision: .character(" "), edit: edit(0, " ")))
    }

    @Test func uppercaseAndSymbolsAreReposted() {
        #expect(RepostPolicy.canRepostOriginal(decision: .character("A"), edit: edit(0, "A")))
        #expect(RepostPolicy.canRepostOriginal(decision: .character("@"), edit: edit(0, "@")))
    }

    @Test func anyBackspaceForbidsRepost() {
        #expect(!RepostPolicy.canRepostOriginal(decision: .character("a"), edit: edit(1, "a")))
    }

    @Test func textDifferentFromTheTypedKeyForbidsRepost() {
        // the engine composed something else (tone, macro, capitalization)
        #expect(!RepostPolicy.canRepostOriginal(decision: .character("s"), edit: edit(0, "á")))
        #expect(!RepostPolicy.canRepostOriginal(decision: .character("a"), edit: edit(0, "A")))
        #expect(!RepostPolicy.canRepostOriginal(decision: .character("a"), edit: edit(0, "ab")))
        #expect(!RepostPolicy.canRepostOriginal(decision: .character("a"), edit: edit(0, "")))
    }

    @Test func nonCharacterDecisionsNeverRepost() {
        let others: [KeyDecision] = [.backspace, .commitPassthrough, .commitCaretMove,
                                     .commitNewline, .commitChord, .passthrough]
        for d in others {
            #expect(!RepostPolicy.canRepostOriginal(decision: d, edit: edit(0, "a")))
        }
    }

    @Test func realEngineSequenceMarksOnlyTheBareAppends() {
        let c = EngineController(config: shippedConfig)
        var verdicts: [Bool] = []
        for ch in "tas" {   // t, a append as typed; s adds a tone (backspace + á)
            let r = c.handle(letter(ch))
            verdicts.append(r.edit.map { RepostPolicy.canRepostOriginal(decision: r.decision, edit: $0) } ?? false)
        }
        #expect(verdicts == [true, true, false])
    }
}
