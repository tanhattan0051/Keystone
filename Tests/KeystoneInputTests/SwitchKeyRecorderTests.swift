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
        #expect(SwitchKeyRecorder.action(keyCode: escape, modifiers: [], comboModifiers: []) == .cancelConsume)
    }

    @Test func plainKeysAreRecorded() {
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: [], comboModifiers: []) == .record)
        #expect(SwitchKeyRecorder.action(keyCode: space, modifiers: [], comboModifiers: []) == .record)
    }

    @Test func shiftOptionControlDoNotChangeRecording() {
        // Only the keyCode is stored; the combo's modifiers come from the checkboxes.
        let cases: [ModifierSet] = [[.shift], [.option], [.control], [.control, .option, .shift]]
        for modifiers in cases {
            #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: modifiers, comboModifiers: []) == .record)
        }
    }

    @Test func commandChordsCancelAndPassThroughWhenComboLacksCommand() {
        // ⌘ is not part of the combo, so ⌘W / ⌘Q / ⌘, are app shortcuts.
        #expect(SwitchKeyRecorder.action(keyCode: letterW, modifiers: [.command], comboModifiers: []) == .cancelPassThrough)
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: [.command, .shift], comboModifiers: [.shift]) == .cancelPassThrough)
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: [.command, .option, .control, .shift], comboModifiers: [.control, .option]) == .cancelPassThrough)
    }

    @Test func commandChordIsRecordedWhenComboIncludesCommand() {
        // The user is pressing their own chord (⌘⇧ + K), like any shortcut recorder.
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: [.command], comboModifiers: [.command]) == .record)
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: [.command, .shift], comboModifiers: [.command, .shift]) == .record)
    }

    @Test func plainKeyIsRecordedWhenComboIncludesCommand() {
        #expect(SwitchKeyRecorder.action(keyCode: letterA, modifiers: [], comboModifiers: [.command]) == .record)
    }

    @Test func escapeWinsOverCommand() {
        // Escape is the documented cancel key and is never a hot key, so it is
        // consumed even with ⌘ held, whether or not the combo includes ⌘.
        #expect(SwitchKeyRecorder.action(keyCode: escape, modifiers: [.command], comboModifiers: []) == .cancelConsume)
        #expect(SwitchKeyRecorder.action(keyCode: escape, modifiers: [.command], comboModifiers: [.command]) == .cancelConsume)
    }

    @Test func escapeWithOtherModifiersStillCancels() {
        #expect(SwitchKeyRecorder.action(keyCode: escape, modifiers: [.shift, .option], comboModifiers: []) == .cancelConsume)
    }
}
