// SwitchKeyDetectorTests.swift — pins the modifier-only chord state machine
// behind "Phím chuyển" (switch-language hot key, Phase 4).
//
// NOTE: the live NSEvent monitor wiring in AppModel.bootstrap() is
// integration-only and not unit-testable headless (same reasoning as the
// CGEventTap itself — see EventTapController). What's pinned here is the
// pure detector (`SwitchKeyDetector`) that the live wiring is built on.

import Testing
@testable import KeystoneInput

@Suite("SwitchKeyDetector")
struct SwitchKeyDetectorTests {
    private let controlShift: ModifierSet = [.control, .shift]

    @Test func cleanPressThenReleaseFires() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }

    @Test func otherKeyPressedMidChordCancels() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        detector.otherKeyPressed()
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func addingOutOfTargetModifierCancels() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift, .command]) == false)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func disabledTargetNeverFires() {
        var detector = SwitchKeyDetector(target: nil)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func emptyTargetNeverFires() {
        var detector = SwitchKeyDetector(target: [])
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func emptyReleaseWithoutEverArmingDoesNotFire() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func reArmingAfterCleanFireFiresAgain() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == true)

        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }

    // MARK: - Arbitrary targets (SwitchHotKey feature: modifiers are no
    // longer limited to the four fixed `SwitchKeyModifier` chords)

    @Test func singleModifierTargetFires() {
        var detector = SwitchKeyDetector(target: [.option])
        #expect(detector.flagsChanged(active: [.option]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }

    @Test func threeModifierTargetFires() {
        let target: ModifierSet = [.control, .option, .shift]
        var detector = SwitchKeyDetector(target: target)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .option]) == false)
        #expect(detector.flagsChanged(active: [.control, .option, .shift]) == false)
        #expect(detector.flagsChanged(active: [.option, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }

    @Test func threeModifierTargetCancelledByFourthModifier() {
        let target: ModifierSet = [.control, .option, .shift]
        var detector = SwitchKeyDetector(target: target)
        #expect(detector.flagsChanged(active: [.control, .option, .shift]) == false)
        #expect(detector.flagsChanged(active: [.control, .option, .shift, .command]) == false)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func optionCommandTargetFires() {
        let target: ModifierSet = [.option, .command]
        var detector = SwitchKeyDetector(target: target)
        #expect(detector.flagsChanged(active: [.command]) == false)
        #expect(detector.flagsChanged(active: [.option, .command]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }

    @Test func optionCommandTargetOtherKeyPressedCancels() {
        let target: ModifierSet = [.option, .command]
        var detector = SwitchKeyDetector(target: target)
        #expect(detector.flagsChanged(active: [.option, .command]) == false)
        detector.otherKeyPressed()
        #expect(detector.flagsChanged(active: []) == false)
    }

    // MARK: - A target that is a SUBSET of a larger held chord (arbitrary
    // single/multi-modifier targets, Phase 7) must never re-arm just because
    // the chord later shrinks down to exactly `target`.

    @Test func targetSubsetOfHeldChordDoesNotFireOnCommandReleasedFirst() {
        // Redo (⌘⇧Z) with target=[.shift]: ⌘ and ⇧ go down together, Z is
        // pressed, then ⌘ is released FIRST — leaving active == target. That
        // must not look like a clean press-then-release of target.
        var detector = SwitchKeyDetector(target: [.shift])
        #expect(detector.flagsChanged(active: [.command]) == false)
        #expect(detector.flagsChanged(active: [.command, .shift]) == false)
        detector.otherKeyPressed()   // Z keyDown
        #expect(detector.flagsChanged(active: [.shift]) == false)   // release ⌘ first
        #expect(detector.flagsChanged(active: []) == false)         // release ⇧ — must not fire
    }

    @Test func defaultTargetDoesNotFireWhenOptionReleasedFirstFromThreeModifierChord() {
        // ⌃⌥⇧+key with target=⌃⇧: releasing ⌥ first leaves active == target,
        // but a real key was pressed while ⌥ (outside target) was also held.
        let target: ModifierSet = [.control, .shift]
        var detector = SwitchKeyDetector(target: target)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .option]) == false)
        #expect(detector.flagsChanged(active: [.control, .option, .shift]) == false)
        detector.otherKeyPressed()
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)   // release ⌥
        #expect(detector.flagsChanged(active: []) == false)                  // release rest
    }

    // MARK: - A key typed with no modifier held is not part of any hold.

    @Test func keyTypedBeforeTheChordDoesNotBlockIt() {
        // "test" then ⌃⇧: the letters' keyDowns arrive while nothing is held.
        var detector = SwitchKeyDetector(target: controlShift)
        detector.otherKeyPressed()
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }

    @Test func editPostedRightAfterAFireDoesNotBlockTheNextChord() {
        // Turning Vietnamese off posts the word's commit edit (synthetic
        // keyDowns the monitors also see) after the release; an immediate ⌃⇧
        // back on must still fire.
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == true)
        detector.otherKeyPressed()
        detector.otherKeyPressed()
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }

    @Test func mouseDownBeforeTheChordStillBlocksIt() {
        // Monitors see no mouse-up: a drag with ⇧ (or ⌥) pressed mid-drag must
        // not look like a clean single-modifier chord.
        var detector = SwitchKeyDetector(target: [.shift])
        detector.mouseDown()
        #expect(detector.flagsChanged(active: [.shift]) == false)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func mouseDownMidChordCancels() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        detector.mouseDown()
        #expect(detector.flagsChanged(active: []) == false)
    }
}
