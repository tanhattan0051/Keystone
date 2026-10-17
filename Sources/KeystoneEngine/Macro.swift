// Macro.swift — pure types and matching for macro expansion ("gõ tắt"),
// Phase 4. See DECISIONS.md "Macros / gõ tắt" for the resolved design
// (spec Open Question #9): macros fire at word commit against the RAW
// keystroke buffer, case-sensitively, and take precedence over both
// Vietnamese rendering and restore-if-invalid. This file only holds the
// pure data + matching/parsing logic; the firing sites live in Engine.swift
// (Vietnamese-mode, inside `finalize`) and (English-mode, `processInactive`
// / `flushInactive`).

/// One configured macro: typing `trigger` (the literal raw keys of a word)
/// and then committing it (a boundary character or flush) replaces it with
/// `replacement`.
public struct MacroRule: Sendable, Equatable, Codable {
    public var trigger: String
    public var replacement: String
    public var enabled: Bool
    /// "Gõ tắt cả khi tắt tiếng Việt" — also expand while Vietnamese input is off.
    public var expandInEnglishMode: Bool
    /// Uppercase the replacement's first letter at a sentence start. Off by
    /// default per-macro, so the feature is dormant until a macro opts in
    /// AND the global `EngineConfig.macroAutoCapitalize` is also on.
    public var autoCapitalize: Bool

    public init(
        trigger: String,
        replacement: String,
        enabled: Bool = true,
        expandInEnglishMode: Bool = false,
        autoCapitalize: Bool = false
    ) {
        self.trigger = trigger
        self.replacement = replacement
        self.enabled = enabled
        self.expandInEnglishMode = expandInEnglishMode
        self.autoCapitalize = autoCapitalize
    }
}

/// A matchable set of macros, built once per `EngineConfig` change (not
/// rebuilt per keystroke — see `Engine`'s cached `macroTable`).
public struct MacroTable: Sendable, Equatable {
    private var rulesByTrigger: [String: MacroRule]

    /// Keeps only `enabled` rules with a non-empty trigger, keyed by
    /// `trigger`. If more than one enabled rule shares a trigger, the LAST
    /// one in `rules` wins (a disabled rule is dropped before this step, so
    /// it can never shadow an earlier enabled rule with the same trigger).
    /// An empty trigger is rejected here as a safety net: it would otherwise
    /// match the empty raw buffer and fire on every bare commit.
    public init(_ rules: [MacroRule]) {
        var map: [String: MacroRule] = [:]
        for rule in rules where rule.enabled && !rule.trigger.isEmpty {
            map[rule.trigger] = rule
        }
        self.rulesByTrigger = map
    }

    /// The rule for `rawTyped`, if any, gated by English mode: a rule only
    /// fires while Vietnamese input is off when it opted in via
    /// `expandInEnglishMode`. Matching is exact and case-sensitive.
    public func match(_ rawTyped: String, englishMode: Bool) -> MacroRule? {
        guard let rule = rulesByTrigger[rawTyped] else { return nil }
        guard !englishMode || rule.expandInEnglishMode else { return nil }
        return rule
    }

    /// `rule.replacement`, honoring capitalization: only when the macro
    /// itself opted in (`rule.autoCapitalize`), the user's global toggle is
    /// on (`globalAutoCapitalize`), the cursor is at a sentence start, and
    /// the replacement's first character is a lowercase letter — otherwise
    /// the replacement is returned unchanged.
    public static func expandedText(for rule: MacroRule, atSentenceStart: Bool, globalAutoCapitalize: Bool) -> String {
        guard rule.autoCapitalize, globalAutoCapitalize, atSentenceStart,
              let first = rule.replacement.first, first.isLowercase else {
            return rule.replacement
        }
        return first.uppercased() + rule.replacement.dropFirst()
    }

    /// Parse a legacy OpenKey macro file: one `trigger<TAB>replacement` pair
    /// per line. Blank lines, lines without a tab, and lines with an empty
    /// trigger (a leading tab) are skipped; a trailing `\r` (CRLF files) is
    /// trimmed. Returns rules with default flags (`enabled: true`, both
    /// capitalize/English-mode flags off).
    public static func parseTabSeparated(_ text: String) -> [MacroRule] {
        var rules: [MacroRule] = []
        // Split on the raw LINE FEED *scalar*, not `Character`: a Swift
        // `Character` merges a CRLF pair into a single extended grapheme
        // cluster, so splitting on the `Character` "\n" would fail to break
        // CRLF-terminated (Windows-style) lines at all.
        let lfScalar: Unicode.Scalar = "\n"
        let scalarLines = text.unicodeScalars.split(separator: lfScalar, omittingEmptySubsequences: false)
        for scalarLine in scalarLines {
            var line = String(String.UnicodeScalarView(scalarLine))
            if line.hasSuffix("\r") { line.removeLast() }
            guard !line.isEmpty else { continue }
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let trigger = String(line[line.startIndex..<tab])
            guard !trigger.isEmpty else { continue }
            let replacement = String(line[line.index(after: tab)...])
            rules.append(MacroRule(trigger: trigger, replacement: replacement))
        }
        return rules
    }

    // MARK: - Import (OpenKey text files)

    /// Split into lines on the LF *scalar* (a `Character` "\n" would not
    /// break CRLF, see `parseTabSeparated`), trimming one trailing `\r`.
    private static func lines(of text: String) -> [String] {
        let lfScalar: Unicode.Scalar = "\n"
        return text.unicodeScalars
            .split(separator: lfScalar, omittingEmptySubsequences: false)
            .map { scalarLine in
                var line = String(String.UnicodeScalarView(scalarLine))
                if line.hasSuffix("\r") { line.removeLast() }
                return line
            }
    }

    private static func strippingBOM(_ text: String) -> String {
        text.unicodeScalars.first == "\u{FEFF}" ? String(String.UnicodeScalarView(text.unicodeScalars.dropFirst())) : text
    }

    /// Sniff the text format: a leading `;` line is OpenKey's header; else a
    /// TAB anywhere means the legacy tab format; else assume a headerless
    /// `name:content` list.
    public static func detectTextFormat(_ text: String) -> MacroTextFormat {
        let body = strippingBOM(text)
        if let first = lines(of: body).first, first.hasPrefix(";") { return .openKey }
        return body.unicodeScalars.contains("\t") ? .tabSeparated : .openKey
    }

    /// Parse an OpenKey export (tuyenvm/OpenKey `Macro.cpp`, `readFromFile`):
    /// split each line at its FIRST ':'; lines without ':' are skipped. A name
    /// that starts with ':' ends up empty after that split, so OpenKey
    /// re-splits the content to let names like ":D" work (":D:smile" ->
    /// ":D"/"smile", "::x" -> ":"/"x"). Empty content is allowed; empty
    /// names are skipped.
    ///
    /// OpenKey drops the first line unconditionally (it is always the
    /// header). We drop it only when it starts with ";" so a headerless
    /// list does not lose its first macro. Duplicates are NOT removed here;
    /// `rulesToAdd` does that against the existing list.
    public static func parseOpenKey(_ text: String) -> [MacroRule] {
        var allLines = lines(of: strippingBOM(text))
        if let first = allLines.first, first.hasPrefix(";") { allLines.removeFirst() }

        var rules: [MacroRule] = []
        for line in allLines {
            let scalars = Array(line.unicodeScalars)
            guard let firstColon = scalars.firstIndex(of: ":") else { continue }
            var name = Array(scalars[..<firstColon])
            var content = Array(scalars[(firstColon + 1)...])
            // Mirrors OpenKey's `while (name == "" && content != "")` loop.
            while name.isEmpty, !content.isEmpty {
                guard let colon = content.firstIndex(of: ":") else { break }
                name.append(":")
                name.append(contentsOf: content[..<colon])
                content = Array(content[(colon + 1)...])
            }
            guard !name.isEmpty else { continue }
            rules.append(MacroRule(
                trigger: String(String.UnicodeScalarView(name)),
                replacement: String(String.UnicodeScalarView(content))
            ))
        }
        return rules
    }

    /// Detect the text format and parse accordingly.
    public static func parseLegacyText(_ text: String) -> [MacroRule] {
        switch detectTextFormat(text) {
        case .openKey: return parseOpenKey(text)
        case .tabSeparated: return parseTabSeparated(strippingBOM(text))
        }
    }

    /// Which of `incoming` to append to a list that already has
    /// `existingTriggers` (OpenKey's append mode: an existing name is kept,
    /// the first occurrence in the file wins). Empty triggers are dropped
    /// silently and are NOT counted as duplicates. Order and flags preserved.
    public static func rulesToAdd(
        _ incoming: [MacroRule],
        existingTriggers: Set<String>
    ) -> (toAdd: [MacroRule], skippedDuplicates: Int) {
        var seen = existingTriggers
        var toAdd: [MacroRule] = []
        var skipped = 0
        for rule in incoming where !rule.trigger.isEmpty {
            if seen.insert(rule.trigger).inserted {
                toAdd.append(rule)
            } else {
                skipped += 1
            }
        }
        return (toAdd, skipped)
    }
}

// MARK: - Trigger validation

/// Why a macro trigger can never fire. The engine only matches a trigger
/// against the RAW keys it accumulated for one word, so a trigger containing
/// anything the engine never accumulates is silently dead.
public enum MacroTriggerProblem: Equatable, Sendable {
    case empty
    case containsWhitespace
    /// A letter that is not ASCII a-z / A-Z (e.g. "đ", "á", "ư"): those are
    /// composed outputs, never raw keys.
    case nonRawLetter(Character)
    /// Not a word character for the input method, so typing it ends the word
    /// before the trigger is complete.
    case boundaryCharacter(Character)

    /// Short Vietnamese explanation, shown inline under the trigger field.
    public var message: String {
        switch self {
        case .empty:
            return "Gõ tắt đang trống."
        case .containsWhitespace:
            return "Gõ tắt không được chứa khoảng trắng: khoảng trắng kết thúc từ nên gõ tắt sẽ không bao giờ khớp."
        case .nonRawLetter(let ch):
            return "Ký tự \"\(ch)\" không phải phím gõ thô nên gõ tắt sẽ không bao giờ khớp. Hãy nhập đúng các phím bạn gõ (ví dụ \"ddc\" thay cho \"đc\")."
        case .boundaryCharacter(let ch):
            return "Ký tự \"\(ch)\" kết thúc từ ở kiểu gõ hiện tại nên gõ tắt sẽ không khớp khi bật tiếng Việt (chỉ có thể khớp khi tắt tiếng Việt)."
        }
    }
}

extension MacroTable {
    /// The first reason `trigger` can never fire, or nil when it can.
    ///
    /// Duplicates the engine's private `Engine.isWordChar` for Vietnamese
    /// mode: letters always; VNI adds digits; every other method adds "[" and
    /// "]". A macro ALWAYS fires in Vietnamese mode and optionally also in
    /// English mode (which accumulates letters + numbers only), so a
    /// character must be a Vietnamese-mode word char to be valid. Hence a
    /// "k2" macro in Telex is reported as `.boundaryCharacter` even with
    /// `expandInEnglishMode` — it could only fire with Vietnamese off.
    /// `expandInEnglishMode` is therefore accepted for call-site clarity but
    /// does not widen the valid set. The behavioural cross-check in
    /// MacroTriggerValidationTests pins this copy to the real engine.
    public static func triggerProblem(
        _ trigger: String,
        inputMethod: InputMethod,
        expandInEnglishMode: Bool
    ) -> MacroTriggerProblem? {
        guard !trigger.isEmpty else { return .empty }
        for ch in trigger {
            if ch.isWhitespace { return .containsWhitespace }
            if ch.isLetter {
                if !ch.isASCII { return .nonRawLetter(ch) }
                continue
            }
            let isVietnameseWordChar: Bool
            switch inputMethod {
            case .vni: isVietnameseWordChar = ch.isNumber
            default:   isVietnameseWordChar = ch == "[" || ch == "]"
            }
            if !isVietnameseWordChar { return .boundaryCharacter(ch) }
        }
        return nil
    }
}

/// Text formats a macro file can be in (JSON is handled by the app layer).
public enum MacroTextFormat: Equatable, Sendable {
    /// OpenKey's own export: `;Compatible OpenKey ...` header, then `name:content` lines.
    case openKey
    /// Legacy `trigger<TAB>replacement` lines.
    case tabSeparated
}
