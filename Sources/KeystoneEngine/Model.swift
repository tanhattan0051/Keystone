// Model.swift — core value types for the pure engine.
//
// Everything here is deterministic and side-effect free. The engine consumes a
// `KeyInput` plus an `EngineConfig` and returns an `EngineResult`
// { backspaceCount, text }. See the design spec, Part A §1.

/// The six Vietnamese tones (thanh điệu).
public enum Tone: UInt8, Sendable, Equatable, Codable {
    case ngang = 0   // level, no mark
    case huyen       // ` grave      (à)
    case sac         // ´ acute      (á)
    case hoi         // ̉ hook above (ả)
    case nga         // ˜ tilde      (ã)
    case nang        // ̣ dot below  (ạ)

    /// The Unicode combining scalar used to build the precomposed form.
    /// `ngang` has no combining mark.
    var combining: Unicode.Scalar? {
        switch self {
        case .ngang: return nil
        case .huyen: return "\u{0300}"
        case .sac:   return "\u{0301}"
        case .hoi:   return "\u{0309}"
        case .nga:   return "\u{0303}"
        case .nang:  return "\u{0323}"
        }
    }
}

/// A nucleus base vowel, stripped of quality mark and tone.
public enum BaseVowel: UInt8, Sendable, Equatable, Codable {
    case a, e, i, o, u, y

    init?(_ ch: Character) {
        switch ch {
        case "a": self = .a
        case "e": self = .e
        case "i": self = .i
        case "o": self = .o
        case "u": self = .u
        case "y": self = .y
        default:  return nil
        }
    }

    var letter: Character {
        switch self {
        case .a: return "a"
        case .e: return "e"
        case .i: return "i"
        case .o: return "o"
        case .u: return "u"
        case .y: return "y"
        }
    }
}

/// The quality mark carried by a vowel (dấu phụ nguyên âm).
public enum VowelMark: UInt8, Sendable, Equatable, Codable {
    case none
    case circumflex   // ˆ : a→â, e→ê, o→ô
    case breve        // ˘ : a→ă
    case horn         // ̛ : o→ơ, u→ư
}

/// Modern (kiểu mới: hòa, thủy) vs classic (kiểu cũ: hoà, thuỷ) tone placement.
public enum Orthography: String, Sendable, Equatable, Codable {
    case modern
    case classic
}

/// Input method family. Phase 1 implements `.telex`; the rest are Phase 3.
public enum InputMethod: String, Sendable, Equatable, Codable {
    case telex
    case vni
    case simpleTelex1
    case simpleTelex2
}

/// Output code table. Phase 1 implements `.unicode` (NFC precomposed).
public enum CodeTable: String, Sendable, Equatable, Codable {
    case unicode          // Unicode NFC precomposed (default, internal canonical)
    case unicodeCompound  // combining diacritics (tổ hợp)  — Phase 3
    case tcvn3            // ABC                            — Phase 3
    case vniWindows       // VNI-Windows                    — Phase 3
    case cp1258           // Windows-1258                    — Phase 3
}

/// Engine configuration snapshot. Immutable value the engine reads per keystroke.
public struct EngineConfig: Sendable, Equatable, Codable {
    public var inputMethod: InputMethod
    public var codeTable: CodeTable
    public var orthography: Orthography
    /// When true, an invalid syllable is reverted to raw keystrokes at commit.
    public var restoreIfInvalid: Bool
    /// "Quick Telex" (gõ nhanh): typing a consonant twice in a row expands it
    /// to the matching digraph/trigraph onset (cc→ch, gg→gi, kk→kh, nn→ng,
    /// pp→ph, qq→qu, tt→th). Off by default (design spec Part A §2.6). Note
    /// dd→đ is a separate, always-on rule and is not gated by this flag.
    public var quickTelex: Bool
    /// "Cho phép gõ tắt" (Phase 4, macro expansion). Off by default — the
    /// feature ships dormant until explicitly turned on.
    public var macrosEnabled: Bool
    /// "Gõ tắt cả khi tắt tiếng Việt" — also let macros fire while Vietnamese
    /// input is off (routes through `Engine.processInactive`/`flushInactive`).
    public var macrosExpandWhenVietnameseOff: Bool
    /// Global switch for macro-triggered sentence-start capitalization. A
    /// macro also needs its own `MacroRule.autoCapitalize` on for this to
    /// take effect — see `MacroTable.expandedText`.
    public var macroAutoCapitalize: Bool
    /// The configured macro rules (see `MacroRule`/`MacroTable`).
    public var macros: [MacroRule]
    /// "Gõ tắt phụ âm đầu" (Phase 4, Telex only): a lone f/j/w typed as the
    /// word's very FIRST keystroke expands to its digraph onset (f→ph, j→gi,
    /// w→qu) instead of its usual tone/horn duty. Off by default — see
    /// DECISIONS.md "Quick consonants & auto-capitalize".
    public var quickStartConsonant: Bool
    /// "Gõ tắt phụ âm cuối" (Phase 4, Telex only): g/h/k typed immediately
    /// after a vowel (closing the nucleus) expands to its digraph coda
    /// (g→ng, h→nh, k→ch). Off by default.
    public var quickEndConsonant: Bool
    /// "Viết hoa đầu câu" (Phase 4): capitalizes the first letter of the word
    /// committed at a sentence start, reusing `Engine`'s `atSentenceStart`
    /// tracking. Off by default; distinct from `macroAutoCapitalize` (which
    /// only affects macro expansions).
    public var autoCapitalize: Bool
    /// "Cho phép bỏ dấu tự do" (design spec Part A §4 — free tone-mark
    /// placement). When true (the default — preserves existing behavior and
    /// the full corpus), a quality mark (circumflex/breve/horn) or đ may
    /// apply non-adjacently, to the nearest eligible earlier letter, not only
    /// right after it: `roiof`→rồi, `toiws`→tới, `dangd`→đang (Telex); VNI
    /// `moi71`→mới, `dang9`→đang. When false, marks/đ apply ONLY when
    /// adjacent to their target — the non-adjacent branches don't fire and
    /// the key falls through to literal/append, same as any other rejected
    /// non-adjacent application. Tones are syllable-level and unaffected
    /// either way. See DECISIONS.md "Positional (non-adjacent) marks".
    public var allowFreeToneMark: Bool
    /// "Bỏ dấu ở cuối từ (kể cả sau phụ âm)" (Phase 4). Off by default — an
    /// opt-in EXTENSION of `allowFreeToneMark`'s non-adjacent placement, not a
    /// replacement for it. When true:
    /// - Telex circumflex (a/e/o) may land on a vowel across a consonant
    ///   coda, not only within the trailing vowel run: `trene`→trên.
    /// - Telex/VNI đ may stroke a still-OPEN syllable's onset `d`, not only
    ///   an adjacent `dd` or an already-closed syllable: `dadng`→đang.
    /// Tradeoff accepted on purpose: the same mechanism turns some English
    /// words Vietnamese (`mama`→mâm, `dad`→đa) when this is on. Default
    /// false keeps the corpus and English-word protection exactly as today.
    /// See DECISIONS.md "Bỏ dấu ở cuối từ / freeMarkAcrossCoda (Phase 4)".
    public var freeMarkAcrossCoda: Bool
    /// "Huỷ dấu xong thì gõ tiếp chữ thường" (Phase 6, OpenKey-compatible
    /// cancel semantics). Off by default. A Telex/VNI tone or quality-mark
    /// CANCEL is the standard same-key double-strike (Telex ss/ff/rr/xx/jj
    /// tones; aa/ee/oo circumflex, dd's đ-stroke, w's horn/breve — all the
    /// existing double-strike "undo" branches in `Telex.fold`/`VNI.fold`; VNI
    /// digits 1-5 tones and 6/7/8/9 marks the same way). `z` (tone-clear) is
    /// NOT a cancel here — unlike the keys above it doesn't double a letter
    /// to undo anything, it just clears the tone outright (see DECISIONS.md
    /// "`z` key semantics"), so typing `z` never enters this mode. When
    /// `literalAfterCancel` is true, once a cancel fires anywhere in the
    /// composing word, EVERY LATER key of that same word is taken completely
    /// literally — no tone, no quality mark, no quick-telex/quick-consonant
    /// transform — until the word boundary. This mirrors OpenKey's
    /// `tempDisableKey` (see DECISIONS.md "OpenKey-compatible
    /// literal-after-cancel (Phase 6)"). Default false keeps the corpus and
    /// every existing Telex/VNI test byte-identical; only later keys within
    /// the SAME word after a cancel are affected — everything before the
    /// cancel is unchanged either way.
    public var literalAfterCancel: Bool
    /// "Kiểm tra chính tả" (Phase 7, eager restore). Off by default. When
    /// true, `Engine.rerender` (per-keystroke, WHILE the word is still being
    /// typed) renders the raw keystrokes literally as soon as the composing
    /// word becomes a Vietnamese syllable that is DEAD — structurally unable
    /// to ever become legal no matter what is typed next (see `Engine`'s
    /// private `isUnrecoverable(_:)`, right next to `isValid(_:)`). This is a
    /// STRICTER, EARLIER cousin of `restoreIfInvalid` (which only reverts at
    /// the word boundary and gates on merely "currently invalid," not
    /// "dead") — it lets an English word like `docker`/`vmware`/`faster`
    /// show as itself while typing, instead of flashing pseudo-Vietnamese
    /// until Space. Default false keeps the corpus and every existing test
    /// byte-identical; see DECISIONS.md "Eager restore (spellCheck / Phase
    /// 7)" for the dead-vs-merely-invalid distinction and the safety
    /// guarantee (every real Vietnamese word renders identically on or off).
    public var spellCheck: Bool

    public init(
        inputMethod: InputMethod = .telex,
        codeTable: CodeTable = .unicode,
        orthography: Orthography = .modern,
        restoreIfInvalid: Bool = true,
        quickTelex: Bool = false,
        macrosEnabled: Bool = false,
        macrosExpandWhenVietnameseOff: Bool = false,
        macroAutoCapitalize: Bool = true,
        macros: [MacroRule] = [],
        quickStartConsonant: Bool = false,
        quickEndConsonant: Bool = false,
        autoCapitalize: Bool = false,
        allowFreeToneMark: Bool = true,
        freeMarkAcrossCoda: Bool = false,
        literalAfterCancel: Bool = false,
        spellCheck: Bool = false
    ) {
        self.inputMethod = inputMethod
        self.codeTable = codeTable
        self.orthography = orthography
        self.restoreIfInvalid = restoreIfInvalid
        self.quickTelex = quickTelex
        self.macrosEnabled = macrosEnabled
        self.macrosExpandWhenVietnameseOff = macrosExpandWhenVietnameseOff
        self.macroAutoCapitalize = macroAutoCapitalize
        self.macros = macros
        self.quickStartConsonant = quickStartConsonant
        self.quickEndConsonant = quickEndConsonant
        self.autoCapitalize = autoCapitalize
        self.allowFreeToneMark = allowFreeToneMark
        self.freeMarkAcrossCoda = freeMarkAcrossCoda
        self.literalAfterCancel = literalAfterCancel
        self.spellCheck = spellCheck
    }
}

/// One keystroke fed to the engine. Case is carried in the character itself.
public struct KeyInput: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case character(Character)
        case backspace
    }
    public var kind: Kind

    public init(kind: Kind) { self.kind = kind }
    public init(_ ch: Character) { self.kind = .character(ch) }
    public static let backspace = KeyInput(kind: .backspace)
}

/// The engine's instruction to the input layer: delete `backspaceCount` code
/// units of the active table, then type `text`.
public struct EngineResult: Sendable, Equatable {
    public var backspaceCount: Int
    public var text: String
    public init(backspaceCount: Int, text: String) {
        self.backspaceCount = backspaceCount
        self.text = text
    }
    public static let none = EngineResult(backspaceCount: 0, text: "")
}
