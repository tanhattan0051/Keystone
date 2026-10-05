// KeystrokeExecutor.swift — turns an EngineResult into sink calls.
//
// Kept separate from EventTapController so it can be unit-tested against a
// fake EventSink without any CGEventTap machinery.

import KeystoneEngine

public struct KeystrokeExecutor {
    public let sink: EventSink

    public init(sink: EventSink) {
        self.sink = sink
    }

    /// Placeholder typed before the backspaces by `clearInlineSuggestion`
    /// (U+202F narrow no-break space — OpenKey's `SendEmptyCharacter`). It is
    /// a real insertion, so it REPLACES any selected inline-autocomplete
    /// suffix; the extra Backspace that follows then removes the placeholder
    /// instead of the suggestion. U+202F because it is invisible, rarely
    /// typed, and not treated as a word separator by browsers.
    public static let inlineSuggestionPlaceholder = "\u{202F}"

    /// - Parameter eachGrapheme: "Gửi từng phím" — when true, post `result.text`
    ///   one `Character` (grapheme cluster) at a time instead of a single
    ///   `postText` call. Defaults to false so existing call sites compile
    ///   unchanged.
    /// - Parameter clearInlineSuggestion: "Sửa lỗi gợi ý" — Chrome's omnibox
    ///   (and similar fields) keeps an inline-autocomplete suffix SELECTED
    ///   after the caret, so the first synthetic Backspace only deletes that
    ///   selection and the character we meant to replace survives ("hoô").
    ///   When true and there is something to delete, type a placeholder
    ///   first (replacing the selection) and send one extra Backspace for it.
    ///   Net zero when the field keeps the placeholder. Skipped when
    ///   `backspaceCount == 0`: a plain insertion already replaces a
    ///   selection by itself.
    public func execute(
        _ result: EngineResult,
        eachGrapheme: Bool = false,
        clearInlineSuggestion: Bool = false
    ) {
        if result.backspaceCount > 0 {
            if clearInlineSuggestion {
                sink.postText(Self.inlineSuggestionPlaceholder)
                sink.postBackspace(count: result.backspaceCount + 1)
            } else {
                sink.postBackspace(count: result.backspaceCount)
            }
        }
        guard !result.text.isEmpty else { return }
        if eachGrapheme {
            for ch in result.text { sink.postText(String(ch)) }
        } else {
            sink.postText(result.text)
        }
    }
}
