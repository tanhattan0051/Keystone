// RefreshThrottleTests.swift — pins the leading+trailing throttle semantics
// of `RefreshThrottle` (Sources/KeystoneInput/RefreshThrottle.swift), which
// App/KeyFocusTracker.swift uses to rate-limit its AX focus re-check.
//
// Every offset below is a power-of-two fraction (0.0625 = 1/16, 0.125 = 1/8,
// 0.25 = 1/4, …) so the expected `.runAfter` remaining is exactly
// representable in Double and the equality checks below can't flake on
// floating-point rounding.

import Testing
@testable import KeystoneInput

@Suite("RefreshThrottle")
struct RefreshThrottleTests {
    @Test func firstRequestRunsNow() {
        var throttle = RefreshThrottle(interval: 0.25)
        #expect(throttle.request(at: 0) == .runNow)
    }

    @Test func requestInsideWindowRunsAfterExactRemaining() {
        var throttle = RefreshThrottle(interval: 0.25)
        throttle.didRun(at: 10.0)
        #expect(throttle.request(at: 10.0625) == .runAfter(0.1875))
    }

    @Test func secondRequestWhileScheduledIsAlreadyScheduled() {
        var throttle = RefreshThrottle(interval: 0.25)
        throttle.didRun(at: 10.0)
        _ = throttle.request(at: 10.0625)   // schedules a trailing run
        #expect(throttle.request(at: 10.125) == .alreadyScheduled)
    }

    @Test func afterTrailingRunAnotherInWindowRequestRunsAfterAgain() {
        var throttle = RefreshThrottle(interval: 0.25)
        throttle.didRun(at: 10.0)
        _ = throttle.request(at: 10.0625)   // schedules a trailing run
        throttle.didRun(at: 10.25)          // the scheduled trailing run fires
        #expect(throttle.request(at: 10.3125) == .runAfter(0.1875))
    }

    @Test func requestExactlyAtIntervalRunsNow() {
        var throttle = RefreshThrottle(interval: 0.25)
        throttle.didRun(at: 10.0)
        #expect(throttle.request(at: 10.25) == .runNow)
    }

    @Test func requestAfterIntervalRunsNow() {
        var throttle = RefreshThrottle(interval: 0.25)
        throttle.didRun(at: 10.0)
        #expect(throttle.request(at: 11.0) == .runNow)
    }

    @Test func nowBeforeLastRunRunsNow() {
        var throttle = RefreshThrottle(interval: 0.25)
        throttle.didRun(at: 10.0)
        #expect(throttle.request(at: 9.0) == .runNow)
    }
}
