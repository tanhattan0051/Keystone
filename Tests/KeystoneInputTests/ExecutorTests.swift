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
    func postForwardDelete() {}
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

// MARK: - inlineSuggestionClearing ("Sửa lỗi gợi ý" inline-autocomplete fix)
//
// Order matters here (placeholder text BEFORE the backspaces), which the
// two-array FakeSink above cannot express, so these use a single ordered log.

private enum Op: Equatable {
    case text(String)
    case backspace(Int)
    case forwardDelete
}

private final class OrderSink: EventSink {
    var ops: [Op] = []
    func postBackspace(count: Int) { ops.append(.backspace(count)) }
    func postText(_ text: String) { ops.append(.text(text)) }
    func postForwardDelete() { ops.append(.forwardDelete) }
}

@Suite("Executor inlineSuggestionClearing")
struct ExecutorInlineSuggestionTests {
    private let placeholder = "\u{202F}"

    @Test func flagOnWithBackspaceTypesPlaceholderThenOneExtraBackspace() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 1, text: "ô"), inlineSuggestionClearing: .placeholder)
        #expect(sink.ops == [.text(placeholder), .backspace(2), .text("ô")])
    }

    @Test func flagOnWithoutBackspaceIsUnchanged() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 0, text: "a"), inlineSuggestionClearing: .placeholder)
        #expect(sink.ops == [.text("a")])
    }

    @Test func flagOffIsUnchanged() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 2, text: "việt"), inlineSuggestionClearing: .none)
        #expect(sink.ops == [.backspace(2), .text("việt")])
    }

    @Test func flagOnWithEachGraphemeSendsPlaceholderOnce() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 2, text: "việt"), eachGrapheme: true, inlineSuggestionClearing: .placeholder)
        #expect(sink.ops == [.text(placeholder), .backspace(3),
                             .text("v"), .text("i"), .text("ệ"), .text("t")])
    }

    @Test func flagOnWithBackspaceAndEmptyTextSendsNoText() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 3, text: ""), inlineSuggestionClearing: .placeholder)
        #expect(sink.ops == [.text(placeholder), .backspace(4)])
    }

    @Test func forwardDeleteComesFirstThenBackspacesThenText() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 1, text: "w"), inlineSuggestionClearing: .forwardDelete)
        #expect(sink.ops == [.forwardDelete, .backspace(1), .text("w")])
    }

    @Test func forwardDeleteDoesNotChangeTheBackspaceCount() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 3, text: ""), inlineSuggestionClearing: .forwardDelete)
        #expect(sink.ops == [.forwardDelete, .backspace(3)])
    }

    @Test func noForwardDeleteWithoutBackspace() {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 0, text: "a"), inlineSuggestionClearing: .forwardDelete)
        #expect(sink.ops == [.text("a")])
    }

    @Test(arguments: [InlineSuggestionClearing.none, .placeholder])
    func noForwardDeleteUnlessRequested(mode: InlineSuggestionClearing) {
        let sink = OrderSink()
        KeystrokeExecutor(sink: sink)
            .execute(EngineResult(backspaceCount: 2, text: "việt"), inlineSuggestionClearing: mode)
        #expect(!sink.ops.contains(.forwardDelete))
    }
}
