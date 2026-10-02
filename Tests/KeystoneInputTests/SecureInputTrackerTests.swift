// SecureInputTrackerTests.swift — pins the OFF→ON / ON→OFF semantics and the
// exact status strings of `SecureInputTracker`
// (Sources/KeystoneInput/SecureInputTracker.swift), which App/AppModel.swift
// polls to show "Secure Input is on" and to stop learning per-app state.

import Testing
@testable import KeystoneInput

@Suite("SecureInputTracker")
struct SecureInputTrackerTests {
    @Test func initialStateIsInactiveWithNoHolder() {
        let tracker = SecureInputTracker()
        #expect(tracker.isActive == false)
        #expect(tracker.holder == nil)
    }

    @Test func offToOnCapturesFrontmostNameAsHolder() {
        var tracker = SecureInputTracker()
        let change = tracker.update(isEnabled: true, frontmostAppName: "Google Chrome")
        #expect(change == .began(holder: "Google Chrome"))
        #expect(tracker.isActive)
        #expect(tracker.holder == "Google Chrome")
    }

    @Test func offToOnWithUnknownFrontmostHasNilHolder() {
        var tracker = SecureInputTracker()
        let change = tracker.update(isEnabled: true, frontmostAppName: nil)
        #expect(change == .began(holder: nil))
        #expect(tracker.isActive)
        #expect(tracker.holder == nil)
    }

    @Test func holderIsKeptWhileOnEvenWhenFrontmostChanges() {
        // kCGSSessionSecureInputPID-style attribution would follow the
        // frontmost app; the tracker must pin the app that was frontmost
        // when Secure Input BEGAN, because only then is the guess sound.
        var tracker = SecureInputTracker()
        _ = tracker.update(isEnabled: true, frontmostAppName: "Google Chrome")
        let change = tracker.update(isEnabled: true, frontmostAppName: "Discord")
        #expect(change == nil)
        #expect(tracker.isActive)
        #expect(tracker.holder == "Google Chrome")
    }

    @Test func onToOffClearsActiveAndHolder() {
        var tracker = SecureInputTracker()
        _ = tracker.update(isEnabled: true, frontmostAppName: "Google Chrome")
        let change = tracker.update(isEnabled: false, frontmostAppName: "Discord")
        #expect(change == .ended)
        #expect(tracker.isActive == false)
        #expect(tracker.holder == nil)
    }

    @Test func repeatedIdenticalSamplesReturnNil() {
        var tracker = SecureInputTracker()
        #expect(tracker.update(isEnabled: false, frontmostAppName: "Finder") == nil)
        #expect(tracker.update(isEnabled: false, frontmostAppName: "Finder") == nil)
        #expect(tracker.update(isEnabled: true, frontmostAppName: "Finder") == .began(holder: "Finder"))
        #expect(tracker.update(isEnabled: true, frontmostAppName: "Finder") == nil)
        #expect(tracker.update(isEnabled: true, frontmostAppName: "Finder") == nil)
    }

    @Test func offOnOffOnReattributesToNewFrontmost() {
        var tracker = SecureInputTracker()
        _ = tracker.update(isEnabled: true, frontmostAppName: "Google Chrome")
        _ = tracker.update(isEnabled: false, frontmostAppName: "Google Chrome")
        let change = tracker.update(isEnabled: true, frontmostAppName: "Safari")
        #expect(change == .began(holder: "Safari"))
        #expect(tracker.holder == "Safari")
    }

    @Test func statusMessageNamesTheHolder() {
        #expect(SecureInputTracker.statusMessage(holder: "Google Chrome")
            == "Google Chrome đang bật nhập bảo mật (ô mật khẩu) — thoát ô/tab đó để gõ tiếng Việt")
    }

    @Test func statusMessageWithoutHolderIsGeneric() {
        #expect(SecureInputTracker.statusMessage(holder: nil)
            == "Một ứng dụng đang bật nhập bảo mật (ô mật khẩu) — thoát ô/tab đó để gõ tiếng Việt")
    }
}
