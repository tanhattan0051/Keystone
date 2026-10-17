// SwitchKeyRecorderTests.swift — pins the pure decision the "Phím kèm:"
// recorder makes for each keyDown while armed. See
// `SwitchKeyRecorder.action` in `Sources/KeystoneInput/SwitchHotKey.swift`.

import Testing
@testable import KeystoneInput

@Suite("SwitchKeyRecorder — action")
struct SwitchKeyRecorderTests {
    private let escape: UInt16 = 53
    private let letterA: UInt16 = 0
    private let space: UInt16 = 49
    private let letterW: UInt16 = 13

    @Test func escapeCancelsAndIsConsumed() {
        #expect(SwitchKeyRecorder.action(keyCode: escape, modifiers: []) == .cancelConsume)
    }

    @Test func plainKeysAreRecorded() {
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: []) == .record)
        #expect(SwitchKeyRecorder.action(keyCode: space, modifiers: []) == .record)
    }

    @Test func shiftOptionControlDoNotChangeRecording() {
        // Only the keyCode is stored; the combo's modifiers come from the checkboxes.
        let cases: [ModifierSet] = [[.shift], [.option], [.control], [.control, .option, .shift]]
        for modifiers in cases {
            #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: modifiers) == .record)
        }
    }

    @Test func commandChordsCancelAndPassThrough() {
        #expect(SwitchKeyRecorder.action(keyCode: letterW, modifiers: [.command]) == .cancelPassThrough)
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: [.command, .shift]) == .cancelPassThrough)
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: [.command, .option, .control, .shift]) == .cancelPassThrough)
    }

    @Test func escapeWinsOverCommand() {
        // Escape is the documented cancel key and is never a hot key, so it is
        // consumed even with ⌘ held.
        #expect(SwitchKeyRecorder.action(keyCode: escape, modifiers: [.command]) == .cancelConsume)
    }

    @Test func escapeWithOtherModifiersStillCancels() {
        #expect(SwitchKeyRecorder.action(keyCode: escape, modifiers: [.shift, .option]) == .cancelConsume)
    }
}
