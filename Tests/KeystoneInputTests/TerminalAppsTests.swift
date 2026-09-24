// TerminalAppsTests.swift — pins the pure bundle-id check that App/AppModel.swift
// uses to mask sentence auto-capitalize while a terminal emulator is
// frontmost (see DECISIONS.md "Không tự viết hoa trong Terminal").

import Testing
@testable import KeystoneInput

@Suite("TerminalApps")
struct TerminalAppsTests {
    @Test(
        arguments: [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp-Preview",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.github.wez.wezterm",
            "co.zeit.hyper",
            "org.tabby",
        ]
    )
    func knownTerminalsAreRecognized(bundleID: String) {
        #expect(TerminalApps.isTerminal(bundleID: bundleID))
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(TerminalApps.isTerminal(bundleID: "COM.GOOGLECODE.ITERM2"))
        #expect(TerminalApps.isTerminal(bundleID: "com.panic.Prompt.3"))
    }

    @Test func nilBundleIDIsNotATerminal() {
        #expect(!TerminalApps.isTerminal(bundleID: nil))
    }

    @Test func emptyStringIsNotATerminal() {
        #expect(!TerminalApps.isTerminal(bundleID: ""))
    }

    @Test(
        arguments: [
            "com.apple.TextEdit",
            "com.microsoft.VSCode",
            "com.google.Chrome",
            "com.apple.finder",
            "com.tanta.keystone",
        ]
    )
    func ordinaryAppsAreNotTerminals(bundleID: String) {
        #expect(!TerminalApps.isTerminal(bundleID: bundleID))
    }

    @Test(
        arguments: [
            "com.apple.Terminal.helper",
            "com.googlecode",
            "org.alacritty2",
            "iterm2",                  // input is a suffix of a known id
            "Terminal",                // input is a suffix of a known id
            "x.com.apple.Terminal",    // a known id is a suffix of the input
        ]
    )
    func partialMatchesAreNotTerminals(bundleID: String) {
        #expect(!TerminalApps.isTerminal(bundleID: bundleID))
    }
}

// MARK: - capitalizationCanFire

/// Pins `TerminalApps.capitalizationCanFire`, the mirror of
/// `EngineController.handle`'s own gate: while Vietnamese is active, the
/// engine's normal `autoCapitalize`/macro-triggered capitalization paths run;
/// while inactive, `EngineController.handle` only routes through the engine
/// at all when BOTH `macrosEnabled` and `macrosExpandWhenVietnameseOff` are
/// on (English-mode macros), so capitalization can only fire there via
/// `macroAutoCapitalize` on top of that same pair. `AppModel.needsKeyFocusTracking`
/// uses this to decide whether the AX focus read is worth running at all.
@Suite("TerminalApps.capitalizationCanFire")
struct TerminalAppsCapitalizationCanFireTests {
    // MARK: Vietnamese active — autoCapitalize || (macrosEnabled && macroAutoCapitalize)

    @Test func vietnameseActiveAutoCapitalizeOnFiresRegardlessOfMacros() {
        #expect(TerminalApps.capitalizationCanFire(
            vietnameseEnabled: true,
            autoCapitalize: true,
            macrosEnabled: false,
            macroAutoCapitalize: false,
            macrosExpandWhenVietnameseOff: false
        ))
    }

    @Test func vietnameseActiveMacroPathFiresWithoutAutoCapitalize() {
        #expect(TerminalApps.capitalizationCanFire(
            vietnameseEnabled: true,
            autoCapitalize: false,
            macrosEnabled: true,
            macroAutoCapitalize: true,
            macrosExpandWhenVietnameseOff: false
        ))
    }

    @Test func vietnameseActiveMacrosEnabledButMacroAutoCapitalizeOffDoesNotFire() {
        #expect(!TerminalApps.capitalizationCanFire(
            vietnameseEnabled: true,
            autoCapitalize: false,
            macrosEnabled: true,
            macroAutoCapitalize: false,
            macrosExpandWhenVietnameseOff: false
        ))
    }

    @Test func vietnameseActiveMacroAutoCapitalizeOnButMacrosDisabledDoesNotFire() {
        #expect(!TerminalApps.capitalizationCanFire(
            vietnameseEnabled: true,
            autoCapitalize: false,
            macrosEnabled: false,
            macroAutoCapitalize: true,
            macrosExpandWhenVietnameseOff: false
        ))
    }

    @Test func vietnameseActiveEverythingOffDoesNotFire() {
        #expect(!TerminalApps.capitalizationCanFire(
            vietnameseEnabled: true,
            autoCapitalize: false,
            macrosEnabled: false,
            macroAutoCapitalize: false,
            macrosExpandWhenVietnameseOff: false
        ))
    }

    @Test func vietnameseActiveIgnoresMacrosExpandWhenVietnameseOff() {
        #expect(TerminalApps.capitalizationCanFire(
            vietnameseEnabled: true,
            autoCapitalize: true,
            macrosEnabled: false,
            macroAutoCapitalize: false,
            macrosExpandWhenVietnameseOff: true
        ))
    }

    // MARK: Vietnamese inactive — macrosEnabled && macrosExpandWhenVietnameseOff && macroAutoCapitalize

    @Test func vietnameseInactiveAllThreeMacroFlagsOnFires() {
        #expect(TerminalApps.capitalizationCanFire(
            vietnameseEnabled: false,
            autoCapitalize: true,
            macrosEnabled: true,
            macroAutoCapitalize: true,
            macrosExpandWhenVietnameseOff: true
        ))
    }

    @Test func vietnameseInactiveMacrosDisabledDoesNotFire() {
        #expect(!TerminalApps.capitalizationCanFire(
            vietnameseEnabled: false,
            autoCapitalize: false,
            macrosEnabled: false,
            macroAutoCapitalize: true,
            macrosExpandWhenVietnameseOff: true
        ))
    }

    @Test func vietnameseInactiveMacrosExpandWhenVietnameseOffOffDoesNotFire() {
        #expect(!TerminalApps.capitalizationCanFire(
            vietnameseEnabled: false,
            autoCapitalize: false,
            macrosEnabled: true,
            macroAutoCapitalize: true,
            macrosExpandWhenVietnameseOff: false
        ))
    }

    @Test func vietnameseInactiveMacroAutoCapitalizeOffDoesNotFire() {
        #expect(!TerminalApps.capitalizationCanFire(
            vietnameseEnabled: false,
            autoCapitalize: false,
            macrosEnabled: true,
            macroAutoCapitalize: false,
            macrosExpandWhenVietnameseOff: true
        ))
    }

    @Test func vietnameseInactiveIgnoresAutoCapitalize() {
        #expect(!TerminalApps.capitalizationCanFire(
            vietnameseEnabled: false,
            autoCapitalize: true,
            macrosEnabled: false,
            macroAutoCapitalize: true,
            macrosExpandWhenVietnameseOff: true
        ))
    }
}
