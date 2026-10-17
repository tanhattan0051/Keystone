// SwitchKeyDetector.swift — pure state machine behind "Phím chuyển" (the
// modifier-only global hot key that toggles Vietnamese input on/off, Phase
// 4). Deliberately NOT on the CGEventTap hot path: this only ever runs off
// AppKit `NSEvent` monitors wired up in AppModel — see DECISIONS.md.
//
// A modifier-only chord = the target modifiers pressed together, then
// released cleanly with no other key pressed in between. That "no other key"
// requirement is what keeps ordinary shortcuts like Ctrl+Shift+C from firing
// this — `otherKeyPressed()` cancels the in-progress chord the moment a real
// key comes down while it's armed.

/// The modifier keys `SwitchKeyDetector` can watch for, independent of
/// AppKit's `NSEvent.ModifierFlags` so this module stays platform-neutral and
/// unit-testable headless.
public struct ModifierSet: OptionSet, Sendable, Equatable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = ModifierSet(rawValue: 1 << 0)
    public static let option  = ModifierSet(rawValue: 1 << 1)
    public static let shift   = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)
}

/// Detects a clean press-then-release of `target`'s modifiers, with nothing
/// else pressed in between. Feed every `flagsChanged`/`keyDown` event to it in
/// order; a `true` return from `flagsChanged(active:)` means the caller should
/// toggle Vietnamese input.
public struct SwitchKeyDetector: Sendable {
    /// The chord to watch for. `nil` or empty disables detection entirely.
    public var target: ModifierSet?

    /// True once `active` has exactly matched `target` at some point since
    /// the last full release — i.e. the chord has been "picked up".
    private var armed = false
    /// True once a non-modifier key (or an out-of-target modifier) has been
    /// seen while armed — the chord is still being tracked so a further
    /// out-of-target modifier doesn't re-cancel-then-fire, but it won't fire
    /// on release anymore.
    private var cancelled = false
    /// True from the moment ANY modifier outside `target` or any real key has
    /// been seen during the CURRENT hold — i.e. since `active` was last fully
    /// empty. Unlike `cancelled` (which only matters once armed), this is
    /// sticky for the whole hold and blocks arming in the first place: a
    /// chord that starts as a larger superset of `target` and later shrinks
    /// down to exactly `target` (e.g. ⌘⇧Z with target=[.shift], releasing ⌘
    /// first) must never look "clean" just because `active` happens to equal
    /// `target` again before the final release. Cleared only when `active`
    /// becomes empty (a full release starts a fresh hold).
    private var dirty = false
    /// The modifiers held as of the last `flagsChanged`. Empty means no hold
    /// is in progress, so a key typed now belongs to no chord.
    private var held: ModifierSet = []

    public init(target: ModifierSet? = nil) {
        self.target = target
    }

    /// Feed the current modifier-key state on every `.flagsChanged` event.
    /// Returns true exactly when a clean press→release of `target` just
    /// completed.
    public mutating func flagsChanged(active: ModifierSet) -> Bool {
        held = active
        guard let target, !target.isEmpty else {
            armed = false
            cancelled = false
            dirty = false
            return false
        }

        if active.isEmpty {
            let fire = armed && !cancelled && !dirty
            armed = false
            cancelled = false
            dirty = false
            return fire
        }

        if !active.isSubset(of: target) {
            // A modifier outside `target` is part of this hold — taints the
            // WHOLE hold, even after it's released and `active` shrinks back
            // down to exactly `target`.
            dirty = true
        }

        if active == target {
            if !dirty {
                armed = true
                cancelled = false
            }
            return false
        }

        // Non-empty and not an exact match to `target`.
        guard armed else { return false }
        if active.isSubset(of: target) {
            // A subset of target with at least one target key already
            // released — still on the way down or up, not a new chord.
            return false
        }
        // A modifier outside `target` joined the chord — no longer clean.
        cancelled = true
        return false
    }

    /// Feed every `.keyDown` (a real, non-modifier key) event. Cancels an
    /// already-armed chord and taints the rest of the current hold so it can
    /// never arm later either (see `dirty`).
    ///
    /// A key with no modifier held is ignored: it belongs to no hold, and
    /// tainting the next one would make ⌃⇧ fail right after typing a word, or
    /// right after Vietnamese was switched off (the commit edit posted then is
    /// seen by the monitors too).
    public mutating func otherKeyPressed() {
        guard !held.isEmpty else { return }
        taint()
    }

    /// Feed every mouse-down (see `AppModel.handleSwitchKeyEvent`): a
    /// modifier-click must not toggle. Unlike a key, it taints even with no
    /// modifier held, because the monitors never see the mouse-up: a drag with
    /// ⇧ or ⌥ pressed mid-drag would otherwise look like a clean
    /// single-modifier chord.
    public mutating func mouseDown() {
        taint()
    }

    private mutating func taint() {
        dirty = true
        if armed { cancelled = true }
    }
}
