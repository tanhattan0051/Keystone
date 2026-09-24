// RefreshThrottle.swift — pure leading+trailing throttle, no Foundation
// timers or clocks: the caller supplies "now" (a monotonic seconds value,
// e.g. `ProcessInfo.processInfo.systemUptime`) and drives its own scheduling
// off the `Decision` this returns. Built for App/KeyFocusTracker.swift's AX
// focus re-check, but has no AppKit/AX dependency itself.
//
// Requests arrive on every keystroke (see KeyFocusTracker.requestRefresh()),
// far more often than the AX read should actually run. A request must never
// be DROPPED, though: if one arrives while a run is still "cooling down", it
// has to be remembered and honored once the window closes — otherwise the
// first keystroke typed into a just-summoned floating panel (see
// DECISIONS.md "Floating panels follow keyboard focus, not activation")
// could be classified against the WRONG app and silently lost to the
// throttle. Leading+trailing is the standard shape for that: the first
// request in a quiet period runs immediately (leading edge), and at most one
// more — covering every request that arrived during the cooldown — runs
// right as the window closes (trailing edge).

import Foundation   // TimeInterval only — no Foundation timers/clocks used here

public struct RefreshThrottle: Sendable {
    public enum Decision: Equatable, Sendable {
        case runNow
        case runAfter(TimeInterval)
        case alreadyScheduled
    }

    public let interval: TimeInterval

    /// `now` from the most recent `didRun(at:)`, or `nil` before the first
    /// run.
    private var lastRun: TimeInterval?
    /// Whether a trailing run is already pending — set by a `.runAfter`
    /// decision, cleared by the `didRun(at:)` that reports it fired.
    private var scheduled = false

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// A re-check was requested at `now` (monotonic seconds).
    public mutating func request(at now: TimeInterval) -> Decision {
        guard let lastRun else { return .runNow }
        // Defensive: `now` should never precede the last recorded run on a
        // monotonic clock. Treat it like "never ran" rather than compute a
        // negative remaining — this should not happen, but a caller passing
        // a genuinely monotonic clock must never be able to wedge the
        // throttle into permanently returning stale `.runAfter` delays.
        guard now >= lastRun else { return .runNow }
        let elapsed = now - lastRun
        guard elapsed < interval else { return .runNow }
        guard !scheduled else { return .alreadyScheduled }
        scheduled = true
        return .runAfter(interval - elapsed)
    }

    /// The caller actually ran the re-check at `now` (after `.runNow`, or
    /// when a `.runAfter` fired).
    public mutating func didRun(at now: TimeInterval) {
        scheduled = false
        lastRun = now
    }
}
