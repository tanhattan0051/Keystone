// SwitchHotKey.swift — pure model behind the custom "Phím chuyển" hot key
// (OpenKey-style Vietnamese/English switch), replacing the old fixed
// four-chord `SwitchKeyModifier` enum with a user-recordable combo: any set
// of modifiers (⌃ ⌥ ⇧ ⌘), optionally plus one real key.
//
// Two runtime paths consume this, chosen by whether `key` is set (see
// `AppModel.applySwitchHotKeyRegistration` and DECISIONS.md "Phím chuyển"):
//   - modifier-only → `SwitchKeyDetector` (NSEvent monitors, off the tap).
//   - modifier+key  → Carbon `RegisterEventHotKey` (`App/
//     SwitchHotKeyRegistrar.swift`), which can consume the key outright.
//
// Everything in this file is a pure value type / pure function — no AppKit,
// no Carbon, no I/O — so it stays unit-testable headless like the rest of
// `KeystoneInput`.

import Foundation

/// A user-configured "Phím chuyển" combo: the modifiers alone (a chord,
/// detected on press-then-release), or the modifiers plus one recorded key
/// (registered as a system-wide hot key that fires once on key-down).
public struct SwitchHotKey: Equatable, Sendable, Codable {
    /// One recorded, non-modifier key: its virtual keycode (what gets
    /// registered) plus the display label captured at record time (so the UI
    /// never has to re-derive "Space"/"F5"/etc. from a bare keycode later).
    public struct Key: Equatable, Sendable, Codable {
        public var keyCode: UInt16
        public var label: String

        public init(keyCode: UInt16, label: String) {
            self.keyCode = keyCode
            self.label = label
        }
    }

    public var modifiers: ModifierSet
    public var key: Key?

    public init(modifiers: ModifierSet, key: Key? = nil) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Vietnamese explanation of why this combo can't be used, or `nil` if
    /// it's legal. Two rules:
    ///   1. At least one modifier is required — a bare key isn't a hot key.
    ///   2. If a key IS attached, Shift can't be the only modifier: Shift+key
    ///      is ordinary typing that the engine already processes (see
    ///      `KeyTranslator.decide` — only command/control/option force
    ///      `.resetPassthrough`), so a Shift-only+key combo would silently
    ///      eat every such keystroke instead of typing it.
    public var validationError: String? {
        if modifiers.isEmpty {
            return "Cần chọn ít nhất một phím bổ trợ (⌃ ⌥ ⇧ ⌘)."
        }
        if key != nil && modifiers.isDisjoint(with: [.control, .option, .command]) {
            return "Shift + phím sẽ gõ ra chữ bình thường — cần thêm ⌃, ⌥ hoặc ⌘ vào tổ hợp."
        }
        return nil
    }

    public var isValid: Bool { validationError == nil }

    /// Display string in macOS's standard modifier order (⌃ ⌥ ⇧ ⌘), then the
    /// key's label — e.g. `"⌃ ⇧"`, `"⌃ Space"`, `"⌥ ⌘ Z"`.
    public var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if let key { parts.append(key.label) }
        return parts.isEmpty ? "(chưa đặt)" : parts.joined(separator: " ")
    }
}

extension SwitchHotKey {
    /// Maps the retired `SwitchKeyModifier` raw string (`AppModel`'s old
    /// `Keys.switchKeyModifier` UserDefaults value) to today's shape, for a
    /// one-time read on first launch after upgrading. `"off"` keeps ⌃⇧ as the
    /// stored combo — so re-enabling needs no reconfiguration — but starts
    /// disabled; a missing or unrecognized value (never configured, or a
    /// build newer than this one wrote something this code doesn't know)
    /// falls back to the app's long-standing default, ⌃⇧ enabled.
    public static func migrateLegacy(rawValue: String?) -> (hotKey: SwitchHotKey, isEnabled: Bool) {
        let controlShift = SwitchHotKey(modifiers: [.control, .shift])
        switch rawValue {
        case "optionShift":
            return (SwitchHotKey(modifiers: [.option, .shift]), true)
        case "commandShift":
            return (SwitchHotKey(modifiers: [.command, .shift]), true)
        case "controlOption":
            return (SwitchHotKey(modifiers: [.control, .option]), true)
        case "off":
            return (controlShift, false)
        default:
            // "controlShift", missing, or unrecognized.
            return (controlShift, true)
        }
    }
}

extension SwitchHotKey {
    /// A display label for a recorded key, by virtual keycode (US ANSI
    /// layout, matching the constants already documented at the top of
    /// `KeyTranslator.swift`). Falls back to the captured characters,
    /// uppercased, for ordinary letter/number/symbol keys; and to the bare
    /// keycode for anything neither named nor printable (e.g. a dead key).
    public static func keyLabel(forKeyCode keyCode: UInt16, characters: String) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            return printableLabel(from: characters) ?? "Key \(keyCode)"
        }
    }

    /// Strips control characters and AppKit's private-use "function key"
    /// characters (U+F700–U+F8FF — how `NSEvent.characters` spells
    /// Home/End/PageUp/PageDown/Forward-Delete/F13+ when the keyCode isn't
    /// one of the named cases above) out of a recorded key's characters, then
    /// trims and uppercases what's left. Returns `nil` when nothing printable
    /// remains, so the caller falls back to "Key N" instead of an invisible
    /// or tofu-glyph label.
    private static func printableLabel(from characters: String) -> String? {
        let printableScalars = characters.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) &&
            !(0xF700...0xF8FF).contains(scalar.value)
        }
        let trimmed = String(String.UnicodeScalarView(printableScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }
}

/// What the "Phím kèm:" recorder does with a keyDown while it is armed.
public enum SwitchKeyRecorderAction: Equatable, Sendable {
    /// Store the key as the combo's key and swallow the event.
    case record
    /// Stop recording without storing anything and swallow the event (Escape).
    case cancelConsume
    /// Stop recording without storing anything and let the event through, so
    /// an app shortcut such as ⌘W / ⌘Q / ⌘, still does its normal job.
    case cancelPassThrough
}

/// Pure decision for the recorder's local monitor. Recording suspends the
/// Vietnamese engine system-wide, so any event that signals "the user is
/// doing something else" must end it instead of being captured as the key.
public enum SwitchKeyRecorder {
    private static let escapeKeyCode: UInt16 = 53

    /// Precedence: Escape first (it is the documented cancel key and is never
    /// a valid hot key, so it is consumed even with ⌘ held). Then ⌘: if the
    /// combo already includes ⌘ (checkbox ticked) the user is pressing their
    /// own chord, as in any shortcut recorder, so the key is recorded; if the
    /// combo lacks ⌘, a ⌘ chord (⌘W / ⌘Q / ⌘,) is an app shortcut and cancels
    /// while passing through. Everything else is recorded. Shift/Option/Control
    /// do not matter: only the keyCode is stored, the combo's modifiers come
    /// from the checkboxes.
    public static func action(
        keyCode: UInt16,
        modifiers: ModifierSet,
        comboModifiers: ModifierSet
    ) -> SwitchKeyRecorderAction {
        if keyCode == escapeKeyCode { return .cancelConsume }
        if modifiers.contains(.command) && !comboModifiers.contains(.command) { return .cancelPassThrough }
        return .record
    }
}

extension ModifierSet {
    /// Carbon's `cmdKey`/`shiftKey`/`optionKey`/`controlKey` bit values
    /// (`Carbon.HIToolbox`'s `Events.h`), reproduced here as raw integers so
    /// this pure file stays free of any Carbon/AppKit import — exactly the
    /// mask shape `RegisterEventHotKey` (`App/SwitchHotKeyRegistrar.swift`)
    /// wants for its `inHotKeyModifiers` parameter.
    public var carbonModifierMask: UInt32 {
        var mask: UInt32 = 0
        if contains(.command) { mask |= 0x0100 }
        if contains(.shift) { mask |= 0x0200 }
        if contains(.option) { mask |= 0x0800 }
        if contains(.control) { mask |= 0x1000 }
        return mask
    }
}
