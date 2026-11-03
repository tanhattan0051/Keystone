// MenuBarStateTests.swift — pins the priority order, glyphs, "input stopped"
// flag and exact accessibility labels of `MenuBarState`
// (Sources/KeystoneInput/MenuBarState.swift), which the menu bar icon and the
// "Gõ tiếng Việt" toggle in App/ render from.

import Testing
@testable import KeystoneInput

@Suite("MenuBarState")
struct MenuBarStateTests {
    private func state(
        trusted: Bool = true,
        relaunch: Bool = false,
        secure: Bool = false,
        enabled: Bool = true
    ) -> MenuBarState {
        MenuBarState(
            accessibilityTrusted: trusted,
            needsRelaunch: relaunch,
            secureInputActive: secure,
            enabled: enabled
        )
    }

    // MARK: priority

    @Test func healthyAndEnabledIsVietnamese() {
        #expect(state() == .vietnamese)
    }

    @Test func healthyAndDisabledStaysEnglish() {
        #expect(state(enabled: false) == .english)
    }

    @Test func notTrustedBeatsEverythingElse() {
        #expect(state(trusted: false) == .permissionMissing)
        #expect(state(trusted: false, relaunch: true) == .permissionMissing)
        #expect(state(trusted: false, secure: true) == .permissionMissing)
        #expect(state(trusted: false, relaunch: true, secure: true) == .permissionMissing)
        #expect(state(trusted: false, enabled: false) == .permissionMissing)
    }

    @Test func secureInputBeatsNeedsRelaunch() {
        #expect(state(relaunch: true, secure: true) == .secureInput)
    }

    @Test func secureInputBeatsEnabledAndDisabled() {
        #expect(state(secure: true, enabled: true) == .secureInput)
        #expect(state(secure: true, enabled: false) == .secureInput)
    }

    @Test func needsRelaunchBeatsEnabledAndDisabled() {
        #expect(state(relaunch: true, enabled: true) == .needsRelaunch)
        #expect(state(relaunch: true, enabled: false) == .needsRelaunch)
    }

    // MARK: glyph

    @Test func glyphPerCase() {
        #expect(MenuBarState.vietnamese.glyph == .letter("V"))
        #expect(MenuBarState.english.glyph == .letter("E"))
        #expect(MenuBarState.secureInput.glyph == .systemImage("lock.fill"))
        #expect(MenuBarState.permissionMissing.glyph == .systemImage("exclamationmark.triangle.fill"))
        #expect(MenuBarState.needsRelaunch.glyph == .systemImage("exclamationmark.triangle.fill"))
    }

    // MARK: isInputStopped

    @Test func inputStoppedOnlyWhenPermissionMissingOrNeedsRelaunch() {
        #expect(MenuBarState.permissionMissing.isInputStopped)
        #expect(MenuBarState.needsRelaunch.isInputStopped)
        #expect(MenuBarState.vietnamese.isInputStopped == false)
        #expect(MenuBarState.english.isInputStopped == false)
        // Secure Input is temporary and held by another app.
        #expect(MenuBarState.secureInput.isInputStopped == false)
    }

    // MARK: accessibility labels

    @Test func accessibilityLabelsAreExact() {
        #expect(MenuBarState.vietnamese.accessibilityLabel == "Keystone: đang gõ tiếng Việt")
        #expect(MenuBarState.english.accessibilityLabel == "Keystone: đang gõ tiếng Anh")
        #expect(MenuBarState.secureInput.accessibilityLabel
            == "Keystone: nhập bảo mật đang bật, tạm không gõ được tiếng Việt")
        #expect(MenuBarState.permissionMissing.accessibilityLabel
            == "Keystone: chưa có quyền Accessibility, bộ gõ không chạy")
        #expect(MenuBarState.needsRelaunch.accessibilityLabel
            == "Keystone: cần khởi động lại để bộ gõ chạy")
    }
}
