// InlineAutocompleteTests.swift — end-to-end repro of the Chrome omnibox bug
// (typing Telex "hooj" gives "hoộ") against a faithful model of inline
// autocomplete, and proof that `inlineSuggestionClearing` fixes it.
//
// The omnibox, after each insertion, shows the typed text plus a SELECTED
// suffix from history. The first Backspace therefore deletes only that
// selection, so the engine's "delete 1, type ô" leaves the old "o" behind.
// See DECISIONS.md "Sửa lỗi gợi ý: xoá phần gợi ý tự điền trước khi xoá lùi".

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

private final class InlineAutocompleteField: EventSink {
    private(set) var typed: [Unicode.Scalar] = []
    private var suffix: [Unicode.Scalar] = []
    private let history: [[Unicode.Scalar]]

    init(history: [String]) { self.history = history.map { Array($0.unicodeScalars) } }

    var typedText: String { String(String.UnicodeScalarView(typed)) }
    var visibleText: String { String(String.UnicodeScalarView(typed + suffix)) }

    func postText(_ text: String) {
        suffix = []                       // typing replaces the selection
        typed.append(contentsOf: text.unicodeScalars)
        if let hit = history.first(where: { $0.count > typed.count && $0.starts(with: typed) }) {
            suffix = Array(hit[typed.count...])
        }
    }

    func postBackspace(count: Int) {
        for _ in 0..<count {
            if !suffix.isEmpty { suffix = [] }   // only the selection goes; no re-suggest after a deletion
            else if !typed.isEmpty { typed.removeLast() }
        }
    }

    func postForwardDelete() {}   // the omnibox never receives it (placeholder/none only)
}

/// Model of Spotlight on macOS 27.0.1. Measured by hand: with the grey pill
/// showing, one Delete or one Forward Delete removes only the pill. Assumed,
/// [VERIFY] on device: a pill shows after every insertion, Forward Delete with
/// no pill is a no-op at the end of text, and a deletion does not bring the
/// pill back (edits with bs >= 2 depend on this).
private final class SpotlightField: EventSink {
    private(set) var typed: [Unicode.Scalar] = []
    private(set) var pillShowing = false

    var typedText: String { String(String.UnicodeScalarView(typed)) }

    func postText(_ text: String) {
        typed.append(contentsOf: text.unicodeScalars)
        pillShowing = !typed.isEmpty
    }

    func postBackspace(count: Int) {
        for _ in 0..<count {
            if pillShowing { pillShowing = false }
            else if !typed.isEmpty { typed.removeLast() }
        }
    }

    func postForwardDelete() {
        pillShowing = false   // nothing after the caret otherwise
    }
}

private func type(_ keys: [RawKey], history: [String], fix: Bool) -> String {
    let field = InlineAutocompleteField(history: history)
    let engine = EngineController(config: EngineConfig())
    let executor = KeystrokeExecutor(sink: field)
    for key in keys {
        // Vietnamese active: every character is suppressed, so the edit is the whole effect.
        // Gate routed through the same helper the tap uses.
        let (_, edit, decision) = engine.handle(key)
        if let edit {
            executor.execute(
                edit,
                inlineSuggestionClearing: InlineSuggestionFix.clearing(
                    configured: fix ? .placeholder : .none, decision: decision, edit: edit)
            )
        }
    }
    return field.typedText
}

private func typeIntoSpotlight(_ keys: [RawKey], clearing: InlineSuggestionClearing) -> String {
    let field = SpotlightField()
    let engine = EngineController(config: EngineConfig())
    let executor = KeystrokeExecutor(sink: field)
    for key in keys {
        let (_, edit, decision) = engine.handle(key)
        if let edit {
            executor.execute(
                edit,
                inlineSuggestionClearing: InlineSuggestionFix.clearing(
                    configured: clearing, decision: decision, edit: edit)
            )
        }
    }
    return field.typedText
}

private func type(_ telex: String, history: [String], fix: Bool) -> String {
    type(telex.map(letter), history: history, fix: fix)
}

@Suite("Inline autocomplete")
struct InlineAutocompleteTests {
    @Test func omniboxBugWithoutFix() {
        #expect(type("hooj", history: ["hostinger.com"], fix: false) == "hoộ")
    }

    @Test func omniboxFixed() {
        #expect(type("hooj", history: ["hostinger.com"], fix: true) == "hộ")
    }

    @Test(arguments: [
        ("hooj", "hostinger.com", "hộ"),
        ("vieejt", "vietnix.vn", "việt"),
        ("dduwowcj", "duolingo.com", "được"),
        ("chaof", "chao.vn", "chào"),          // backspaceCount >= 2 against a live selection
        ("nguyeenx", "nguyen.vn", "nguyễn"),
    ])
    func vietnameseWordsMatchComposedResultWithFix(telex: String, entry: String, expected: String) {
        #expect(type(telex, history: [entry], fix: false) != expected)   // the bug is real for this word
        #expect(type(telex, history: [entry], fix: true) == expected)
        #expect(type(telex, history: [], fix: false) == expected)
    }

    @Test func userBackspaceDismissesOnlyTheSuggestion() {
        // Native Chrome: "face" + Delete removes the selected suggestion, keeps "face".
        let keys = "face".map(letter) + [BACKSPACE]
        #expect(type(keys, history: ["facebook.com"], fix: true) == "face")
    }

    @Test func backspaceThatReRendersStaysCorrectUnderASuggestion() {
        // The engine re-renders "viêt" (bs=2, "êt") after ⌫ over a tone key; a
        // live selection must not eat the first of those backspaces.
        let keys = "vieetj".map(letter) + [BACKSPACE]
        let expected = type(keys, history: [], fix: false)
        #expect(expected == "viêt")
        #expect(type(keys, history: ["việt nam"], fix: true) == expected)
    }

    @Test func backspaceThenToneKeyStaysCorrectUnderASuggestion() {
        let keys = "hooj".map(letter) + [BACKSPACE] + [letter("j")]
        let expected = type(keys, history: [], fix: false)
        #expect(expected == "hộ")
        #expect(type(keys, history: ["hộ chiếu"], fix: true) == expected)
    }

    @Test(arguments: ["hooj", "vieejt", "dduwowcj", "tooi", "xin chaof"])
    func emptyHistoryIsNetZero(telex: String) {
        #expect(type(telex, history: [], fix: true) == type(telex, history: [], fix: false))
    }
}

@Suite("Spotlight completion pill")
struct SpotlightPillTests {
    private func keys(_ telex: String) -> [RawKey] { telex.map(letter) }

    @Test func wwWithoutClearingLeavesTheReportedStrayW() {
        #expect(typeIntoSpotlight(keys("ww"), clearing: .none) == "ưw")
    }

    @Test func wwWithForwardDeleteIsW() {
        #expect(typeIntoSpotlight(keys("ww"), clearing: .forwardDelete) == "w")
    }

    @Test(arguments: ["uww", "hooj", "dduwowcj", "vieejt"])
    func forwardDeleteMatchesAFieldWithNoPill(telex: String) {
        let expected = type(telex, history: [], fix: false)
        #expect(typeIntoSpotlight(keys(telex), clearing: .forwardDelete) == expected)
    }

    @Test func usersPureBackspaceStillDismissesOnlyThePill() {
        let all = keys("face") + [BACKSPACE]
        #expect(typeIntoSpotlight(all, clearing: .forwardDelete) == "face")
    }
}
