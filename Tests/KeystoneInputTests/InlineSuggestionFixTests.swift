// InlineSuggestionFixTests.swift — pins the pure per-app gate for the
// inline-autocomplete workaround (see DECISIONS.md "Sửa lỗi gợi ý: xoá phần
// gợi ý tự điền trước khi xoá lùi").

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("InlineSuggestionFix")
struct InlineSuggestionFixTests {
    @Test(arguments: ["com.apple.Terminal", "com.googlecode.iterm2", "COM.APPLE.TERMINAL", "dev.warp.Warp-Stable"])
    func disabledInTerminals(id: String) {
        #expect(!InlineSuggestionFix.allowed(bundleID: id))
    }

    @Test(arguments: ["com.apple.Spotlight", "com.apple.spotlight", "COM.APPLE.SPOTLIGHT"])
    func disabledInSpotlight(id: String) {
        #expect(!InlineSuggestionFix.allowed(bundleID: id))
    }

    @Test(arguments: ["com.google.Chrome", "com.apple.Safari", "com.microsoft.Excel", "", String?.none as String?])
    func allowedElsewhere(id: String?) {
        #expect(InlineSuggestionFix.allowed(bundleID: id))
    }

    private static let allDecisions: [KeyDecision] = [
        .character("a"), .backspace, .commitPassthrough, .commitCaretMove,
        .commitNewline, .resetPassthrough, .passthrough,
    ]

    private static let pureDeletion = EngineResult(backspaceCount: 1, text: "")
    private static let rerender = EngineResult(backspaceCount: 2, text: "êt")

    @Test(arguments: allDecisions)
    func appliesToEveryEditExceptPureDeletion(decision: KeyDecision) {
        let edit = EngineResult(backspaceCount: 1, text: "ô")
        #expect(InlineSuggestionFix.appliesToEdit(enabledForApp: true, decision: decision, edit: edit))
        #expect(InlineSuggestionFix.appliesToEdit(enabledForApp: true, decision: decision, edit: Self.pureDeletion) == (decision != .backspace))
    }

    @Test func backspaceThatReRendersStillGetsThePlaceholder() {
        #expect(InlineSuggestionFix.appliesToEdit(enabledForApp: true, decision: .backspace, edit: Self.rerender))
    }

    @Test func pureDeletionBackspaceSkipsThePlaceholder() {
        #expect(!InlineSuggestionFix.appliesToEdit(enabledForApp: true, decision: .backspace, edit: Self.pureDeletion))
    }

    @Test(arguments: allDecisions)
    func neverAppliesWhenDisabledForApp(decision: KeyDecision) {
        #expect(!InlineSuggestionFix.appliesToEdit(enabledForApp: false, decision: decision, edit: Self.rerender))
        #expect(!InlineSuggestionFix.appliesToEdit(enabledForApp: false, decision: decision, edit: Self.pureDeletion))
    }

    @Test func trackingNeededOnlyWhenTheEngineCanEmitEdits() {
        func needs(_ fix: Bool, _ vi: Bool, _ macros: Bool, _ viOff: Bool) -> Bool {
            InlineSuggestionFix.needsFocusTracking(
                autoFixSuggestion: fix, vietnameseEnabled: vi,
                macrosEnabled: macros, macrosExpandWhenVietnameseOff: viOff)
        }
        #expect(!needs(false, true, true, true))      // toggle off: never
        #expect(needs(true, true, false, false))      // Vietnamese on
        #expect(!needs(true, false, false, false))    // engine idle
        #expect(!needs(true, false, true, false))     // macros on but not expanded while Vietnamese is off
        #expect(!needs(true, false, false, true))
        #expect(needs(true, false, true, true))       // English-mode macros can edit
    }
}
