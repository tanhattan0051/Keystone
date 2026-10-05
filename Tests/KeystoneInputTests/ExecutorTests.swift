// ExecutorTests.swift — KeystrokeExecutor against a recording fake EventSink.
//
// Verifies that an EngineResult is translated into the right sink calls,
// in the right order, and that zero-valued fields produce no call at all.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

private final class FakeSink: EventSink {
    var backspaces: [Int] = []
    var texts: [String] = []

    func postBackspace(count: Int) { backspaces.append(count) }
    func postText(_ text: String) { texts.append(text) }
}

@Suite("Executor")
struct ExecutorTests {
    @Test func backspaceThenText() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 2, text: "x"))
        #expect(sink.backspaces == [2])
        #expect(sink.texts == ["x"])
    }

    @Test func textOnlyWhenNoBackspace() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 0, text: "abc"))
        #expect(sink.backspaces.isEmpty)
        #expect(sink.texts == ["abc"])
    }

    @Test func backspaceOnlyWhenNoText() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 3, text: ""))
        #expect(sink.backspaces == [3])
        #expect(sink.texts.isEmpty)
    }

    @Test func noCallsWhenResultIsEmpty() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 0, text: ""))
        #expect(sink.backspaces.isEmpty)
        #expect(sink.texts.isEmpty)
    }

    // MARK: - eachGrapheme ("Gửi từng phím")
    //
    // The `TapSink` keyDown-only behavior (`autoFixSuggestion`) is
    // production-only/integration, like the rest of the live CGEventTap — it
    // needs a real synthetic CGEvent pair to observe, so it isn't unit-tested
    // here.

    @Test func eachGraphemeFalseSendsWholeStringInOneCall() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 2, text: "việt"), eachGrapheme: false)
        #expect(sink.backspaces == [2])
        #expect(sink.texts == ["việt"])
    }

    @Test func eachGraphemeTrueSendsOneCharacterPerCall() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 2, text: "việt"), eachGrapheme: true)
        #expect(sink.backspaces == [2])
        // "ệ" is a single Swift Character (e + combining dot below + circumflex).
        #expect(sink.texts == ["v", "i", "ệ", "t"])
    }

    @Test func eachGraphemeTrueWithEmptyTextSendsNoText() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 3, text: ""), eachGrapheme: true)
        #expect(sink.backspaces == [3])
        #expect(sink.texts.isEmpty)
    }
}

// MARK: - clearInlineSuggestion ("Sửa lỗi gợi ý" inline-autocomplete fix)
//
// Order matters here (placeholder text BEFORE the backspaces), which the
// two-array FakeSink above cannot express, so these use a single ordered log.

private enum Op: Equatable {
    case text(String)
    case backspace(Int)
}

private final class OrderSink: EventSink {
    var ops: [Op] = []
    func postBackspace(count: Int) { ops.append(.backspace(count)) }
    func postText(_ text: String) { ops.append(.text(text)) }
}

@Suite("Executor clearInlineSuggestion")
struct ExecutorInlineSuggestionTests {
    private let placeholder = "\u{202F}"

    @Test func flagOnWithBackspaceTypesPlaceholderThenOneExtraBackspace() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 1, text: "ô"), clearInlineSuggestion: true)
        #expect(sink.ops == [.text(placeholder), .backspace(2), .text("ô")])
    }

    @Test func flagOnWithoutBackspaceIsUnchanged() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 0, text: "a"), clearInlineSuggestion: true)
        #expect(sink.ops == [.text("a")])
    }

    @Test func flagOffIsUnchanged() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 2, text: "việt"), clearInlineSuggestion: false)
        #expect(sink.ops == [.backspace(2), .text("việt")])
    }

    @Test func flagOnWithEachGraphemeSendsPlaceholderOnce() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 2, text: "việt"), eachGrapheme: true, clearInlineSuggestion: true)
        #expect(sink.ops == [.text(placeholder), .backspace(3),
                             .text("v"), .text("i"), .text("ệ"), .text("t")])
    }

    @Test func flagOnWithBackspaceAndEmptyTextSendsNoText() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 3, text: ""), clearInlineSuggestion: true)
        #expect(sink.ops == [.text(placeholder), .backspace(4)])
    }
}
