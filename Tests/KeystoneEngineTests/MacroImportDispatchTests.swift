import Testing
@testable import KeystoneEngine

// Import safety: JSON-vs-text dispatch, usable-rule filtering, and which
// duplicate wins on replace. Guards against a wrong-shaped or broken JSON
// file wiping the user's list or importing JSON lines as macros.

private let openKeyHeader = ";Compatible OpenKey Macro Data file for UniKey*** version=1 ***"

private func pairs(_ rules: [MacroRule]) -> [String] {
    rules.map { "\($0.trigger)=\($0.replacement)" }
}

@Suite("rulesToAdd duplicate resolution")
struct RulesToAddEnabledDuplicateTests {
    private func rule(_ t: String, _ r: String, enabled: Bool = true) -> MacroRule {
        MacroRule(trigger: t, replacement: r, enabled: enabled)
    }

    @Test func disabledThenEnabledKeepsEnabledAtFirstPosition() {
        let out = MacroTable.rulesToAdd(
            [rule("x", "0"), rule("vn", "off", enabled: false), rule("vn", "on")],
            existingTriggers: [])
        #expect(pairs(out.toAdd) == ["x=0", "vn=on"])
        #expect(out.toAdd[1].enabled)
        #expect(out.skippedDuplicates == 1)
    }

    @Test func lastEnabledWinsOverEarlierEnabled() {
        let out = MacroTable.rulesToAdd(
            [rule("a", "1", enabled: false), rule("a", "2"), rule("a", "3")], existingTriggers: [])
        #expect(pairs(out.toAdd) == ["a=3"])
        #expect(out.skippedDuplicates == 2)
    }

    @Test func laterDisabledDoesNotReplaceKeptEnabled() {
        let out = MacroTable.rulesToAdd([rule("a", "1"), rule("a", "2", enabled: false)], existingTriggers: [])
        #expect(pairs(out.toAdd) == ["a=1"])
        #expect(out.toAdd[0].enabled)
    }

    /// Re-importing an export must keep firing what fired before.
    @Test func reimportFiresSameRuleAsOriginalTable() {
        let patterns: [[MacroRule]] = [
            [rule("vt", "Việt Nam"), rule("vt", "vợ tôi")],
            [rule("vt", "off", enabled: false), rule("vt", "on")],
            [rule("vt", "on"), rule("vt", "off", enabled: false)],
            [rule("vt", "a", enabled: false), rule("vt", "b", enabled: false)],
        ]
        for list in patterns {
            let original = MacroTable(list).match("vt", englishMode: false)
            let reimported = MacroTable(MacroTable.rulesToAdd(list, existingTriggers: []).toAdd)
                .match("vt", englishMode: false)
            #expect(original?.replacement == reimported?.replacement)
        }
    }

    @Test func allDisabledKeepsFirst() {
        let out = MacroTable.rulesToAdd(
            [rule("a", "1", enabled: false), rule("a", "2", enabled: false)], existingTriggers: [])
        #expect(pairs(out.toAdd) == ["a=1"])
        #expect(out.skippedDuplicates == 1)
    }
}

@Suite("import dispatch (JSON vs text)")
struct ImportDispatchTests {
    private struct Boom: Error {}

    private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    /// `json` stands in for the app's JSON decoder result; nil = decode failure.
    private func importRules(_ text: String, json: [MacroRule]? = nil) throws -> [MacroRule] {
        try MacroTable.importRules(
            from: bytes(text),
            decodeJSON: { _ in
                guard let json else { throw Boom() }
                return json
            },
            decodeText: { String(decoding: $0, as: UTF8.self) })
    }

    @Test func looksLikeJSONDetection() {
        #expect(MacroTable.looksLikeJSON(bytes("[{\"trigger\":\"a\"}]")))
        #expect(MacroTable.looksLikeJSON(bytes("  \n\t{\"macros\": []}")))
        #expect(MacroTable.looksLikeJSON([0xEF, 0xBB, 0xBF] + bytes("  [")))
        #expect(MacroTable.looksLikeJSON([0xFF, 0xFE, 0x5B, 0x00]))  // UTF-16LE "["
        #expect(!MacroTable.looksLikeJSON(bytes("vn:Việt Nam")))
        #expect(!MacroTable.looksLikeJSON(bytes(openKeyHeader)))
        #expect(MacroTable.looksLikeJSON(bytes("[]")))
        #expect(MacroTable.looksLikeJSON(bytes("[")))
        #expect(MacroTable.looksLikeJSON(bytes("{ \"macros\": [] }")))
        #expect(!MacroTable.looksLikeJSON(bytes("[c]\t©")))
        #expect(!MacroTable.looksLikeJSON(bytes("{tm}\t™")))
        #expect(!MacroTable.looksLikeJSON(bytes("{:}:ký tự")))
        #expect(!MacroTable.looksLikeJSON(bytes("")))
        #expect(!MacroTable.looksLikeJSON(bytes("   \n")))
    }

    @Test func trailingCommaJSONRethrowsDecodeErrorInsteadOfTextParsing() {
        let broken = "[\n  {\"trigger\": \"vn\", \"replacement\": \"Việt Nam\"},\n]"
        #expect(throws: Boom.self) { try importRules(broken) }
    }

    @Test func prettyPrintedAndMinifiedJSONUseTheJSONDecoder() throws {
        let decoded = [MacroRule(trigger: "vn", replacement: "Việt Nam")]
        let pretty = "[\n  {\n    \"trigger\": \"vn\"\n  }\n]"
        let minified = "[{\"trigger\":\"vn\"}]"
        #expect(try importRules(pretty, json: decoded) == decoded)
        #expect(try importRules(minified, json: decoded) == decoded)
    }

    @Test func objectWrappedAndTruncatedJSONNeverTextParse() {
        #expect(throws: Boom.self) { try importRules("{\"macros\":[{\"trigger\":\"a\"}]}") }
        #expect(throws: Boom.self) { try importRules("[{\"id\": \"x\", \"trigger\": \"a\"") }
    }

    @Test func realOpenKeyFileStillParses() throws {
        let text = "\(openKeyHeader)\nvn:Việt Nam\nko:không\n"
        #expect(pairs(try importRules(text)) == ["vn=Việt Nam", "ko=không"])
    }

    @Test func bracketLeadingTabFileIsTextNotJSON() throws {
        #expect(pairs(try importRules("[c]\t©\n{tm}\t™\n")) == ["[c]=©", "{tm}=™"])
    }

    @Test func headerlessOpenKeyStartingWithBraceIsText() throws {
        #expect(pairs(try importRules("{:}:ký tự\nvn:Việt Nam\n")).contains("vn=Việt Nam"))
    }

    @Test func tabSeparatedFileStillParses() throws {
        #expect(pairs(try importRules("vn\tViệt Nam\n")) == ["vn=Việt Nam"])
    }

    @Test func allEmptyTriggerJSONRulesThrowNoMacrosFound() {
        // Tolerant decoding of [{"name":"vn","text":"Việt Nam"}] gives empty-trigger rules.
        let empties = [MacroRule(trigger: "", replacement: ""), MacroRule(trigger: "", replacement: "x")]
        #expect(throws: MacroImportFailure.noMacrosFound) { try importRules("[{}]", json: empties) }
        #expect(throws: MacroImportFailure.noMacrosFound) { try importRules("[]", json: []) }
    }

    @Test func emptyTriggerRulesAreFilteredOut() throws {
        let mixed = [MacroRule(trigger: "", replacement: "x"), MacroRule(trigger: "a", replacement: "1")]
        #expect(pairs(try importRules("[{}]", json: mixed)) == ["a=1"])
    }

    @Test func textWithNoMacrosThrowsNoMacrosFound() {
        #expect(throws: MacroImportFailure.noMacrosFound) { try importRules("hello world") }
    }

    @Test func undecodableTextThrowsUnreadable() {
        #expect(throws: MacroImportFailure.unreadableText) {
            try MacroTable.importRules(from: [0xC3, 0x28], decodeJSON: { _ in [] }, decodeText: { _ in nil })
        }
    }

    @Test func usableRulesDropsOnlyEmptyTriggers() {
        let rules = [MacroRule(trigger: "", replacement: "x"), MacroRule(trigger: "a", replacement: "")]
        #expect(MacroTable.usableRules(rules).map(\.trigger) == ["a"])
    }
}
